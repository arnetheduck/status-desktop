import NimQml, Tables, json, sequtils, sugar, chronicles, strformat, stint, httpclient, net, strutils, os, times, algorithm
import locks
import web3/[ethtypes, conversions]

import ../settings/service as settings_service
import ../accounts/service as accounts_service
import ../token/service as token_service
import ../network/service as network_service
import ../../common/account_constants
import ../../../app/global/global_singleton

import dto, derived_address, key_pair_dto

import ../../../app/core/eventemitter
import ../../../app/core/signals/types
import ../../../app/core/tasks/[qt, threadpool]
import ../../../backend/accounts as status_go_accounts
import ../../../backend/backend as backend
import ../../../backend/eth as status_go_eth
import ../../../backend/transactions as status_go_transactions

export dto, derived_address, key_pair_dto

logScope:
  topics = "wallet-account-service"

const SIGNAL_WALLET_ACCOUNT_SAVED* = "walletAccount/accountSaved"
const SIGNAL_WALLET_ACCOUNT_DELETED* = "walletAccount/accountDeleted"
const SIGNAL_WALLET_ACCOUNT_CURRENCY_UPDATED* = "walletAccount/currencyUpdated"
const SIGNAL_WALLET_ACCOUNT_TOKEN_VISIBILITY_UPDATED* = "walletAccount/tokenVisibilityUpdated"
const SIGNAL_WALLET_ACCOUNT_UPDATED* = "walletAccount/walletAccountUpdated"
const SIGNAL_WALLET_ACCOUNT_NETWORK_ENABLED_UPDATED* = "walletAccount/networkEnabledUpdated"
const SIGNAL_WALLET_ACCOUNT_DERIVED_ADDRESS_READY* = "walletAccount/derivedAddressesReady"
const SIGNAL_WALLET_ACCOUNT_TOKENS_REBUILT* = "walletAccount/tokensRebuilt"
const SIGNAL_WALLET_ACCOUNT_DERIVED_ADDRESS_DETAILS_FETCHED* = "walletAccount/derivedAddressDetailsFetched"

const SIGNAL_NEW_KEYCARD_SET* = "newKeycardSet"
const SIGNAL_KEYCARD_ACCOUNTS_REMOVED* = "keycardAccountsRemoved"
const SIGNAL_KEYCARD_LOCKED* = "keycardLocked"
const SIGNAL_KEYCARD_UNLOCKED* = "keycardUnlocked"
const SIGNAL_KEYCARD_UID_UPDATED* = "keycardUidUpdated"
const SIGNAL_KEYCARD_NAME_CHANGED* = "keycardNameChanged"

var
  balanceCache {.threadvar.}: Table[string, float64]

proc priorityTokenCmp(a, b: WalletTokenDto): int =
  for symbol in @["ETH", "SNT", "DAI", "STT"]:
    if a.symbol == symbol:
      return -1
    if b.symbol == symbol:
      return 1
  
  cmp(a.name, b.name)

proc hex2Balance*(input: string, decimals: int): string =
  var value = fromHex(Stuint[256], input)

  if decimals == 0:
    return fmt"{value}"

  var p = u256(10).pow(decimals)
  var i = value.div(p)
  var r = value.mod(p)
  var leading_zeros = "0".repeat(decimals - ($r).len)
  var d = fmt"{leading_zeros}{$r}"
  result = $i
  if(r > 0): result = fmt"{result}.{d}"

type AccountSaved = ref object of Args
  account: WalletAccountDto

type AccountDeleted* = ref object of Args
  account*: WalletAccountDto

type CurrencyUpdated = ref object of Args

type TokenVisibilityToggled = ref object of Args

type NetwordkEnabledToggled = ref object of Args

type WalletAccountUpdated* = ref object of Args
  account*: WalletAccountDto

type DerivedAddressesArgs* = ref object of Args
  derivedAddresses*: seq[DerivedAddressDto]
  error*: string

type TokensPerAccountArgs* = ref object of Args
  accountsTokens*: OrderedTable[string, seq[WalletTokenDto]] # [wallet address, list of tokens]

type KeycardActivityArgs* = ref object of Args
  success*: bool
  oldKeycardUid*: string
  keyPair*: KeyPairDto

proc responseHasNoErrors(procName: string, response: RpcResponse[JsonNode]): bool =
  var errMsg = ""
  if not response.error.isNil:
    errMsg = "(" & $response.error.code & ") " & response.error.message
  elif response.result.kind == JObject and response.result.contains("error"):
    errMsg = response.result["error"].getStr
  if(errMsg.len == 0):
    return true
  error "error: ", procName=procName, errDesription = errMsg
  return false

include async_tasks
include  ../../common/json_utils

QtObject:
  type Service* = ref object of QObject
    closingApp: bool
    events: EventEmitter
    threadpool: ThreadPool
    settingsService: settings_service.Service
    accountsService: accounts_service.Service
    tokenService: token_service.Service
    networkService: network_service.Service
    processedKeyPair: KeyPairDto
    walletAccountsLock: Lock
    walletAccounts {.guard: walletAccountsLock.}: OrderedTable[string, WalletAccountDto]

  # Forward declaration
  proc buildAllTokens(self: Service, accounts: seq[string])
  proc checkRecentHistory*(self: Service)
  proc startWallet(self: Service)

  proc delete*(self: Service) =
    self.closingApp = true
    self.QObject.delete

  proc newService*(
    events: EventEmitter,
    threadpool: ThreadPool,
    settingsService: settings_service.Service,
    accountsService: accounts_service.Service,
    tokenService: token_service.Service,
    networkService: network_service.Service,
  ): Service =
    new(result, delete)
    result.QObject.setup
    result.closingApp = false
    result.events = events
    result.threadpool = threadpool
    result.settingsService = settingsService
    result.accountsService = accountsService
    result.tokenService = tokenService
    result.networkService = networkService
    initLock(result.walletAccountsLock)
    withLock result.walletAccountsLock:
      result.walletAccounts = initOrderedTable[string, WalletAccountDto]()

  proc fetchAccounts*(self: Service): seq[WalletAccountDto] =
    let response = status_go_accounts.getAccounts()
    return response.result.getElems().map(
        x => x.toWalletAccountDto()
      ).filter(a => not a.isChat)

  proc setEnsName(self: Service, account: WalletAccountDto) =
    let chainId = self.networkService.getNetworkForEns().chainId
    try:
      let nameResponse = backend.getName(chainId, account.address)
      account.ens = nameResponse.result.getStr
    except Exception as e:
      let errDesription = e.msg
      error "error: ", errDesription
      return

  proc storeAccount*(self: Service, account: WalletAccountDto) =
    withLock self.walletAccountsLock:
      self.walletAccounts[account.address] = account

  proc storeTokensForAccount*(self: Service, address: string, tokens: seq[WalletTokenDto]) =
    withLock self.walletAccountsLock:
      if self.walletAccounts.hasKey(address):
        self.walletAccounts[address].tokens = tokens

  proc removeAccount*(self: Service, address: string): WalletAccountDto =
    result = WalletAccountDto()
    withLock self.walletAccountsLock:
      result = self.walletAccounts[address]
      self.walletAccounts.del(address)

  proc walletAccountsContainsAddress*(self: Service, address: string): bool =
    withLock self.walletAccountsLock:
      result = self.walletAccounts.hasKey(address)

  proc getAccountByAddress*(self: Service, address: string): WalletAccountDto =
    result = WalletAccountDto()
    withLock self.walletAccountsLock:
      if self.walletAccounts.hasKey(address):
        result = self.walletAccounts[address]

  proc getWalletAccounts*(self: Service): seq[WalletAccountDto] =
    withLock self.walletAccountsLock:
      result = toSeq(self.walletAccounts.values)

  proc getAddresses(self: Service): seq[string] =
    withLock self.walletAccountsLock:
      result = toSeq(self.walletAccounts.keys())

  proc init*(self: Service) =
    signalConnect(singletonInstance.localAccountSensitiveSettings, "isWalletEnabledChanged()", self, "onIsWalletEnabledChanged()", 2)
    
    try:
      let accounts = self.fetchAccounts()
      for account in accounts:
        self.setEnsName(account)
        account.relatedAccounts = accounts.filter(x => not account.derivedFrom.isEmptyOrWhitespace and (cmpIgnoreCase(x.derivedFrom, account.derivedFrom) == 0))
        self.storeAccount(account)

      self.buildAllTokens(self.getAddresses())
      self.checkRecentHistory()
      self.startWallet()
    except Exception as e:
      let errDesription = e.msg
      error "error: ", errDesription
      return

    self.events.on(SignalType.Message.event) do(e: Args):
      var receivedData = MessageSignal(e)
      if receivedData.settings.len > 0:
        for settingsField in receivedData.settings:
          if settingsField.name == KEY_CURRENCY:
            self.events.emit(SIGNAL_WALLET_ACCOUNT_CURRENCY_UPDATED, CurrencyUpdated())

    self.events.on(SignalType.Wallet.event) do(e:Args):
      var data = WalletSignal(e)
      case data.eventType:
        of "wallet-tick-reload":
          self.buildAllTokens(self.getAddresses())
          self.checkRecentHistory()
        
  proc getWalletAccount*(self: Service, accountIndex: int): WalletAccountDto =
    let accounts = self.getWalletAccounts()
    if accountIndex < 0 or accountIndex >= accounts.len:
      return
    return accounts[accountIndex]

  proc getIndex*(self: Service, address: string): int =
    let accounts = self.getWalletAccounts()
    for i in 0..accounts.len:
      if(accounts[i].address == address):
        return i

  proc startWallet(self: Service) =
    if(not singletonInstance.localAccountSensitiveSettings.getIsWalletEnabled()):
      return

    discard backend.startWallet()

  proc checkRecentHistory*(self: Service) =
    if(not singletonInstance.localAccountSensitiveSettings.getIsWalletEnabled()):
      return
    
    try:
      let addresses = self.getWalletAccounts().map(a => a.address)
      let chainIds = self.networkService.getNetworks().map(a => a.chainId)
      status_go_transactions.checkRecentHistory(chainIds, addresses)
    except Exception as e:
      let errDescription = e.msg
      error "error: ", errDescription
      return

  proc addNewAccountToLocalStore(self: Service) =
    let accounts = self.fetchAccounts()
    var newAccount = accounts[0]
    for account in accounts:
      if not self.walletAccountsContainsAddress(account.address):
        newAccount = account
        self.setEnsName(newAccount)
        newAccount.relatedAccounts = accounts.filter(x => cmpIgnoreCase(x.derivedFrom, account.derivedFrom) == 0)
        break
    self.storeAccount(newAccount)
    self.buildAllTokens(@[newAccount.address])
    self.events.emit(SIGNAL_WALLET_ACCOUNT_SAVED, AccountSaved(account: newAccount))

  proc addOrReplaceWalletAccount(self: Service, name, address, path, addressAccountIsDerivedFrom, publicKey, keyUid, accountType, 
    color, emoji: string, walletDefaultAccount = false, chatDefaultAccount = false): string =
    try:
      let response = status_go_accounts.saveAccount(name, address, path, addressAccountIsDerivedFrom, publicKey, keyUid, 
        accountType, color, emoji, walletDefaultAccount, chatDefaultAccount)
      if not response.error.isNil:
        return "(" & $response.error.code & ") " & response.error.message
    except Exception as e:
      error "error: ", procName="addWalletAccount", errName = e.name, errDesription = e.msg
      return "error: " & e.msg

  proc generateNewAccount*(self: Service, password: string, accountName: string, color: string, emoji: string, 
    path: string, derivedFrom: string, skipPasswordVerification: bool): string =
    try:
      if skipPasswordVerification:
        discard backend.generateAccountWithDerivedPathPasswordVerified(
          password,
          accountName,
          color,
          emoji,
          path,
          derivedFrom)
      else:
        discard backend.generateAccountWithDerivedPath(
          hashPassword(password),
          accountName,
          color,
          emoji,
          path,
          derivedFrom)
    except Exception as e:
      return fmt"Error generating new account: {e.msg}"

    self.addNewAccountToLocalStore()

  proc addAccountsFromPrivateKey*(self: Service, privateKey: string, password: string, accountName: string, color: string, 
    emoji: string, skipPasswordVerification: bool): string =
    try:
      if skipPasswordVerification:
        discard backend.addAccountWithPrivateKeyPasswordVerified(
          privateKey,
          password,
          accountName,
          color,
          emoji)
      else:
        discard backend.addAccountWithPrivateKey(
          privateKey,
          hashPassword(password),
          accountName,
          color,
          emoji)
    except Exception as e:
      return fmt"Error adding account with private key: {e.msg}"

    self.addNewAccountToLocalStore()

  proc addAccountsFromSeed*(self: Service, mnemonic: string, password: string, accountName: string, color: string, 
    emoji: string, path: string, skipPasswordVerification: bool): string =
    try:
      if skipPasswordVerification:
        discard backend.addAccountWithMnemonicAndPathPasswordVerified(
          mnemonic,
          password,
          accountName,
          color,
          emoji,
          path
        )
      else:
        discard backend.addAccountWithMnemonicAndPath(
          mnemonic,
          hashPassword(password),
          accountName,
          color,
          emoji,
          path
        )
    except Exception as e:
      return fmt"Error adding account with mnemonic: {e.msg}"

    self.addNewAccountToLocalStore()

  proc addWatchOnlyAccount*(self: Service, address: string, accountName: string, color: string, emoji: string): string =
    try:
      discard backend.addAccountWatch(
        address,
        accountName,
        color,
        emoji
      )
    except Exception as e:
      return fmt"Error adding account with mnemonic: {e.msg}"

    self.addNewAccountToLocalStore()

  proc deleteAccount*(self: Service, address: string, keyPairMigrated: bool) =
    try:
      if keyPairMigrated:
        discard status_go_accounts.deleteAccountForMigratedKeypair(address)
      else:
        discard status_go_accounts.deleteAccount(address)
      let accountDeleted = self.removeAccount(address)
      self.events.emit(SIGNAL_WALLET_ACCOUNT_DELETED, AccountDeleted(account: accountDeleted))
    except Exception as e:
      error "error: ", procName="deleteAccount", errName = e.name, errDesription = e.msg    

  proc getCurrency*(self: Service): string =
    return self.settingsService.getCurrency()

  proc updateCurrency*(self: Service, newCurrency: string) =
    discard self.settingsService.saveCurrency(newCurrency)
    self.buildAllTokens(self.getAddresses())
    self.events.emit(SIGNAL_WALLET_ACCOUNT_CURRENCY_UPDATED, CurrencyUpdated())

  proc toggleNetworkEnabled*(self: Service, chainId: int) =
    self.networkService.toggleNetwork(chainId)
    self.events.emit(SIGNAL_WALLET_ACCOUNT_NETWORK_ENABLED_UPDATED, NetwordkEnabledToggled())

  method toggleTestNetworksEnabled*(self: Service) =
    discard self.settingsService.toggleTestNetworksEnabled()
    self.tokenService.init()
    self.checkRecentHistory()
    self.events.emit(SIGNAL_WALLET_ACCOUNT_NETWORK_ENABLED_UPDATED, NetwordkEnabledToggled())

  proc updateWalletAccount*(self: Service, address: string, accountName: string, color: string, emoji: string) =
    if not self.walletAccountsContainsAddress(address):
      error "account's address is not among known addresses: ", address=address
      return
    var account = self.getAccountByAddress(address)
    let res = self.addOrReplaceWalletAccount(accountName, account.address, account.path, account.derivedfrom, 
      account.publicKey, account.keyUid, account.walletType, color, emoji, account.isWallet, account.isChat)
    if res.len == 0:
      account.name = accountName
      account.color = color
      account.emoji = emoji
      self.events.emit(SIGNAL_WALLET_ACCOUNT_UPDATED, WalletAccountUpdated(account: account))

  proc getDerivedAddressList*(self: Service, password: string, derivedFrom: string, path: string, pageSize: int, pageNumber: int, hashPassword: bool)=
    let arg = GetDerivedAddressesTaskArg(
      password: if hashPassword: hashPassword(password) else: password,
      derivedFrom: derivedFrom,
      path: path,
      pageSize: pageSize,
      pageNumber: pageNumber,
      tptr: cast[ByteAddress](getDerivedAddressesTask),
      vptr: cast[ByteAddress](self.vptr),
      slot: "setDerivedAddresses",
    )
    self.threadpool.start(arg)

  proc getDerivedAddressListForMnemonic*(self: Service, mnemonic: string, path: string, pageSize: int, pageNumber: int) =
    let arg = GetDerivedAddressesForMnemonicTaskArg(
      mnemonic: mnemonic,
      path: path,
      pageSize: pageSize,
      pageNumber: pageNumber,
      tptr: cast[ByteAddress](getDerivedAddressesForMnemonicTask),
      vptr: cast[ByteAddress](self.vptr),
      slot: "setDerivedAddresses",
    )
    self.threadpool.start(arg)

  proc getDerivedAddressForPrivateKey*(self: Service, privateKey: string) =
    let arg = GetDerivedAddressForPrivateKeyTaskArg(
      privateKey: privateKey,
      tptr: cast[ByteAddress](getDerivedAddressForPrivateKeyTask),
      vptr: cast[ByteAddress](self.vptr),
      slot: "setDerivedAddresses",
    )
    self.threadpool.start(arg)

  proc setDerivedAddresses*(self: Service, derivedAddressesJson: string) {.slot.} =
    let response = parseJson(derivedAddressesJson)
    var derivedAddress: seq[DerivedAddressDto] = @[]
    derivedAddress = response["derivedAddresses"].getElems().map(x => x.toDerivedAddressDto())
    let error = response["error"].getStr()

    # emit event
    self.events.emit(SIGNAL_WALLET_ACCOUNT_DERIVED_ADDRESS_READY, DerivedAddressesArgs(
      derivedAddresses: derivedAddress,
      error: error
    ))

  proc fetchDerivedAddressDetails*(self: Service, address: string) =
    let arg = FetchDerivedAddressDetailsTaskArg(
      address: address,
      tptr: cast[ByteAddress](fetchDerivedAddressDetailsTask),
      vptr: cast[ByteAddress](self.vptr),
      slot: "onDerivedAddressDetailsFetched",
    )
    self.threadpool.start(arg)

  proc onDerivedAddressDetailsFetched*(self: Service, jsonString: string) {.slot.} =
    var data = DerivedAddressesArgs()
    try:
      let response = parseJson(jsonString)
      let addrDto = response{"details"}.toDerivedAddressDto()
      data.derivedAddresses.add(addrDto)
      data.error = response["error"].getStr()
    except Exception as e:
      error "error: ", procName="getDerivedAddressDetails", errName = e.name, errDesription = e.msg
      data.error = e.msg
    self.events.emit(SIGNAL_WALLET_ACCOUNT_DERIVED_ADDRESS_DETAILS_FETCHED, data)

  proc onAllTokensBuilt*(self: Service, response: string) {.slot.} =
    try:
      let responseObj = response.parseJson
      var data = TokensPerAccountArgs()
      if responseObj.kind == JObject:
        for wAddress, tokensDetailsObj in responseObj:
          if tokensDetailsObj.kind == JArray:
            var tokens: seq[WalletTokenDto]
            tokens = map(tokensDetailsObj.getElems(), proc(x: JsonNode): WalletTokenDto = x.toWalletTokenDto())
            tokens.sort(priorityTokenCmp)
            data.accountsTokens[wAddress] = tokens
            self.storeTokensForAccount(wAddress, tokens)
            self.tokenService.updateTokenPrices(tokens) # For efficiency. Will be removed when token info fetching gets moved to the tokenService
      self.events.emit(SIGNAL_WALLET_ACCOUNT_TOKENS_REBUILT, data)
    except Exception as e:
      error "error: ", procName="onAllTokensBuilt", errName = e.name, errDesription = e.msg

  proc buildAllTokens(self: Service, accounts: seq[string]) =
    if not singletonInstance.localAccountSensitiveSettings.getIsWalletEnabled() or
      accounts.len == 0:
        return

    let arg = BuildTokensTaskArg(
      tptr: cast[ByteAddress](prepareTokensTask),
      vptr: cast[ByteAddress](self.vptr),
      slot: "onAllTokensBuilt",
      accounts: accounts
    )
    self.threadpool.start(arg)

  proc onIsWalletEnabledChanged*(self: Service) {.slot.} =
    self.buildAllTokens(self.getAddresses())
    self.checkRecentHistory()
    self.startWallet()

  proc getCurrentCurrencyIfEmpty(self: Service, currency: string): string =
    if currency != "":
      return currency
    else:
      return self.getCurrency()

  proc getNetworkCurrencyBalance*(self: Service, network: NetworkDto, currency: string = ""): float64 =
    let accounts = self.getWalletAccounts()
    for walletAccount in accounts:
      result += walletAccount.getCurrencyBalance(@[network.chainId], self.getCurrentCurrencyIfEmpty(currency))
       
  proc findTokenSymbolByAddress*(self: Service, address: string): string =
    return self.tokenService.findTokenSymbolByAddress(address)

  proc getCurrencyBalanceForAddress*(self: Service, address: string, currency: string = ""): float64 =
    let chainIds = self.networkService.getNetworks().map(n => n.chainId)
    return self.getAccountByAddress(address).getCurrencyBalance(chainIds, self.getCurrentCurrencyIfEmpty(currency))

  proc getTotalCurrencyBalance*(self: Service, currency: string = ""): float64 =
    let chainIds = self.networkService.getNetworks().filter(a => a.enabled).map(a => a.chainId)
    let accounts = self.getWalletAccounts()
    return accounts.map(a => a.getCurrencyBalance(chainIds, self.getCurrentCurrencyIfEmpty(currency))).foldl(a + b, 0.0)

  proc addMigratedKeyPairAsync*(self: Service, keyPair: KeyPairDto, keyStoreDir: string) =
    let arg = AddMigratedKeyPairTaskArg(
      tptr: cast[ByteAddress](addMigratedKeyPairTask),
      vptr: cast[ByteAddress](self.vptr),
      slot: "onMigratedKeyPairAdded",
      keyPair: keyPair,
      keyStoreDir: keyStoreDir
    )
    self.threadpool.start(arg)

  proc onMigratedKeyPairAdded*(self: Service, response: string) {.slot.} =
    var data = KeycardActivityArgs()
    data.success = false
    try:
      let responseObj = response.parseJson
      discard responseObj.getProp("success", data.success)
      var kpJson: JsonNode
      if responseObj.getProp("keyPair", kpJson):
        data.keyPair = kpJson.toKeyPairDto()
    except Exception as e:
      error "error handilng migrated keypair response", errDesription=e.msg
    self.events.emit(SIGNAL_NEW_KEYCARD_SET, data)

  proc addMigratedKeyPair*(self: Service, keyPair: KeyPairDto, keyStoreDir: string): bool =
    try:
      let response = backend.addMigratedKeyPair(
        keyPair.keycardUid,
        keyPair.keycardName,
        keyPair.keyUid,
        keyPair.accountsAddresses,
        keyStoreDir
        )
      result = responseHasNoErrors("addMigratedKeyPair", response)
      if result:
        self.events.emit(SIGNAL_NEW_KEYCARD_SET, KeycardActivityArgs(success: true, keyPair: keyPair))
    except Exception as e:
      error "error: ", procName="addMigratedKeyPair", errName = e.name, errDesription = e.msg

  proc removeMigratedAccountsForKeycard*(self: Service, keyUid: string, keycardUid: string, accountsToRemove: seq[string]) =
    let arg = RemoveMigratedAccountsForKeycardTaskArg(
      tptr: cast[ByteAddress](removeMigratedAccountsForKeycardTask),
      vptr: cast[ByteAddress](self.vptr),
      slot: "onMigratedAccountsForKeycardRemoved",
      keyPair: KeyPairDto(keyUid: keyUid, keycardUid: keycardUid, accountsAddresses: accountsToRemove)
    )
    self.threadpool.start(arg)

  proc onMigratedAccountsForKeycardRemoved*(self: Service, response: string) {.slot.} =
    var data = KeycardActivityArgs()
    data.success = false
    try:
      let responseObj = response.parseJson
      discard responseObj.getProp("success", data.success)
      var kpJson: JsonNode
      if responseObj.getProp("keyPair", kpJson):
        data.keyPair = kpJson.toKeyPairDto()
    except Exception as e:
      error "error handilng migrated keypair response", errDesription=e.msg
    self.events.emit(SIGNAL_KEYCARD_ACCOUNTS_REMOVED, data)

  proc getAllKnownKeycards*(self: Service): seq[KeyPairDto] = 
    try:
      let response = backend.getAllKnownKeycards()
      if responseHasNoErrors("getAllKnownKeycards", response):
        return map(response.result.getElems(), proc(x: JsonNode): KeyPairDto = toKeyPairDto(x))
    except Exception as e:
      error "error: ", procName="getAllKnownKeycards", errName = e.name, errDesription = e.msg

  proc getAllMigratedKeyPairs*(self: Service): seq[KeyPairDto] = 
    try:
      let response = backend.getAllMigratedKeyPairs()
      if responseHasNoErrors("getAllMigratedKeyPairs", response):
        return map(response.result.getElems(), proc(x: JsonNode): KeyPairDto = toKeyPairDto(x))
    except Exception as e:
      error "error: ", procName="getAllMigratedKeyPairs", errName = e.name, errDesription = e.msg

  proc getMigratedKeyPairByKeyUid*(self: Service, keyUid: string): seq[KeyPairDto] = 
    try:
      let response = backend.getMigratedKeyPairByKeyUID(keyUid)
      if responseHasNoErrors("getMigratedKeyPairByKeyUid", response):
        return map(response.result.getElems(), proc(x: JsonNode): KeyPairDto = toKeyPairDto(x))
    except Exception as e:
      error "error: ", procName="getMigratedKeyPairByKeyUid", errName = e.name, errDesription = e.msg

  proc updateKeycardName*(self: Service, keyUid: string, keycardUid: string, name: string): bool =
    try:
      let response = backend.setKeycardName(keycardUid, name)
      result = responseHasNoErrors("updateKeycardName", response)
      if result:
        let data = KeycardActivityArgs(success: true, keyPair: KeyPairDto(keyUid: keyUid, keycardUid: keycardUid, keycardName: name))
        self.events.emit(SIGNAL_KEYCARD_NAME_CHANGED, data)
    except Exception as e:
      error "error: ", procName="updateKeycardName", errName = e.name, errDesription = e.msg

  proc setKeycardLocked*(self: Service, keyUid: string, keycardUid: string): bool =
    try:
      let response = backend.keycardLocked(keycardUid)
      result = responseHasNoErrors("setKeycardLocked", response)
      if result:
        let data = KeycardActivityArgs(success: true, keyPair: KeyPairDto(keyUid: keyUid, keycardUid: keycardUid))
        self.events.emit(SIGNAL_KEYCARD_LOCKED, data)
    except Exception as e:
      error "error: ", procName="setKeycardLocked", errName = e.name, errDesription = e.msg

  proc setKeycardUnlocked*(self: Service, keyUid: string, keycardUid: string): bool =
    try:
      let response = backend.keycardUnlocked(keycardUid)
      result = responseHasNoErrors("setKeycardUnlocked", response)
      if result:
        let data = KeycardActivityArgs(success: true, keyPair: KeyPairDto(keyUid: keyUid, keycardUid: keycardUid))
        self.events.emit(SIGNAL_KEYCARD_UNLOCKED, data)
    except Exception as e:
      error "error: ", procName="setKeycardUnlocked", errName = e.name, errDesription = e.msg

  proc updateKeycardUid*(self: Service, oldKeycardUid: string, newKeycardUid: string): bool =
    try:
      let response = backend.updateKeycardUID(oldKeycardUid, newKeycardUid)
      result = responseHasNoErrors("updateKeycardUid", response)
      if result:
        let data = KeycardActivityArgs(success: true, oldKeycardUid: oldKeycardUid, keyPair: KeyPairDto(keycardUid: newKeycardUid))
        self.events.emit(SIGNAL_KEYCARD_UID_UPDATED, data)
    except Exception as e:
      error "error: ", procName="updateKeycardUid", errName = e.name, errDesription = e.msg

  proc deleteKeycard*(self: Service, keycardUid: string): bool =
    try:
      let response = backend.deleteKeycard(keycardUid)
      return responseHasNoErrors("deleteKeycard", response)
    except Exception as e:
      error "error: ", procName="deleteKeycard", errName = e.name, errDesription = e.msg
    return false

  proc addWalletAccount*(self: Service, name, address, path, addressAccountIsDerivedFrom, publicKey, keyUid, accountType, 
    color, emoji: string): string =
    result = self.addOrReplaceWalletAccount(name, address, path, addressAccountIsDerivedFrom, publicKey, keyUid, 
      accountType, color, emoji)
    if result.len == 0:
      self.addNewAccountToLocalStore()