import NimQml, random, strutils, marshal, sequtils, sugar, chronicles

import io_interface
import view, controller
import internal/[state, state_factory]
import models/[key_pair_model, key_pair_item]
import ../../../global/global_singleton
import ../../../core/eventemitter

import ../../../../app_service/common/utils
import ../../../../app_service/service/keycard/constants
import ../../../../app_service/service/keycard/service as keycard_service
import ../../../../app_service/service/settings/service as settings_service
import ../../../../app_service/service/privacy/service as privacy_service
import ../../../../app_service/service/accounts/service as accounts_service
import ../../../../app_service/service/wallet_account/service as wallet_account_service
import ../../../../app_service/service/keychain/service as keychain_service

export io_interface

logScope:
  topics = "keycard-popup-module"

type DerivingAccountDetails = object
  keyUid: string
  path: string
  deriveAddressAfterAuthentication: bool
  addressRequested: bool

type
  Module*[T: io_interface.DelegateInterface] = ref object of io_interface.AccessInterface
    delegate: T
    view: View
    viewVariant: QVariant
    controller: Controller
    initialized: bool
    tmpLocalState: State # used when flow is run, until response arrives to determine next state appropriatelly
    authenticationPopupIsAlreadyRunning: bool
    derivingAccountDetails: DerivingAccountDetails

proc newModule*[T](delegate: T,
  uniqueIdentifier: string,
  events: EventEmitter,
  keycardService: keycard_service.Service,
  settingsService: settings_service.Service,
  privacyService: privacy_service.Service,
  accountsService: accounts_service.Service,
  walletAccountService: wallet_account_service.Service,
  keychainService: keychain_service.Service):
  Module[T] =
  result = Module[T]()
  result.delegate = delegate
  result.view = view.newView(result)
  result.viewVariant = newQVariant(result.view)
  result.controller = controller.newController(result, uniqueIdentifier, events, keycardService, settingsService,
    privacyService, accountsService, walletAccountService, keychainService)
  result.initialized = false
  result.authenticationPopupIsAlreadyRunning = false
  result.derivingAccountDetails.deriveAddressAfterAuthentication = false
  result.derivingAccountDetails.addressRequested = false

method delete*[T](self: Module[T]) =
  self.view.delete
  self.viewVariant.delete
  self.controller.delete

proc init[T](self: Module[T]) =
  if not self.initialized:
    self.initialized = true
    self.controller.init()

method getModuleAsVariant*[T](self: Module[T]): QVariant =
  return self.viewVariant

method getPin*[T](self: Module[T]): string =
  return self.controller.getPin()

method getKeycardData*[T](self: Module[T]): string =
  return self.view.getKeycardData()

method setKeycardData*[T](self: Module[T], value: string) =
  self.view.setKeycardData(value)

method setRemainingAttempts*[T](self: Module[T], value: int) =
  self.view.setRemainingAttempts(value)

method setPin*[T](self: Module[T], value: string) =
  self.controller.setPin(value)

method setPuk*[T](self: Module[T], value: string) =
  self.controller.setPuk(value)

method setPassword*[T](self: Module[T], value: string) =
  self.controller.setPassword(value)

method getKeyPairForProcessing*[T](self: Module[T]): KeyPairItem =
  return self.view.getKeyPairForProcessing()

method getKeyPairHelper*[T](self: Module[T]): KeyPairItem =
  return self.view.getKeyPairHelper()

method getNameFromKeycard*[T](self: Module[T]): string =
  return self.controller.getMetadataFromKeycard().name

method setPairingCode*[T](self: Module[T], value: string) =
  self.controller.setPairingCode(value)

method checkRepeatedKeycardPinWhileTyping*[T](self: Module[T], pin: string): bool =
  self.controller.setPinMatch(false)
  let storedPin = self.controller.getPin()
  if pin.len > storedPin.len:
    return false
  elif pin.len < storedPin.len:
    for i in 0 ..< pin.len:
      if pin[i] != storedPin[i]:
        return false
    return true
  else: 
    let match = pin == storedPin
    self.controller.setPinMatch(match)
    return match

method checkRepeatedKeycardPukWhileTyping*[T](self: Module[T], puk: string): bool =
  self.controller.setPukMatch(false)
  let storedPuk = self.controller.getPuk()
  if puk.len > storedPuk.len:
    return false
  elif puk.len < storedPuk.len:
    for i in 0 ..< puk.len:
      if puk[i] != storedPuk[i]:
        return false
    return true
  else: 
    let match = puk == storedPuk
    self.controller.setPukMatch(match)
    return match

method getCurrentFlowType*[T](self: Module[T]): FlowType =
  let currStateObj = self.view.currentStateObj()
  if currStateObj.isNil:
    error "sm_cannot resolve current state in order to determine mnemonic"
    return FlowType.General
  return currStateObj.flowType()

method getMnemonic*[T](self: Module[T]): string =
  let flowType = self.getCurrentFlowType()
  if flowType == FlowType.SetupNewKeycard:
    return self.controller.getProfileMnemonic()
  if flowType == FlowType.SetupNewKeycardNewSeedPhrase or
    flowType == FlowType.SetupNewKeycardOldSeedPhrase:
      return self.controller.getSeedPhrase()

method setSeedPhrase*[T](self: Module[T], value: string) =
  self.controller.setSeedPhrase(value)

method getSeedPhrase*[T](self: Module[T]): string =
  return self.controller.getSeedPhrase()

method validSeedPhrase*[T](self: Module[T], value: string): bool =
  return self.controller.validSeedPhrase(value)

method migratingProfileKeyPair*[T](self: Module[T]): bool =
  return self.controller.getSelectedKeyPairIsProfile()

method getSigningPhrase*[T](self: Module[T]): string =
  return self.controller.getSigningPhrase()

proc preActionActivities[T](self: Module[T], currFlowType: FlowType, currStateType: StateType) =
  if currStateType == StateType.ManageKeycardAccounts or
    currStateType == StateType.CreatePin or
    currStateType == StateType.RepeatPin or
    currStateType == StateType.CreatePuk or
    currStateType == StateType.RepeatPuk or
    currStateType == StateType.EnterPuk or
    currStateType == StateType.WrongPuk:
      self.view.setDisablePopup(false)
      return
  if currStateType == StateType.EnterPin or
    currStateType == StateType.CreatePin or
    currStateType == StateType.RepeatPin or
    currStateType == StateType.WrongPin:
      let disable = self.controller.getPin().len == PINLengthForStatusApp
      self.view.setDisablePopup(disable)
      return
  if currStateType == StateType.CreatePuk or
    currStateType == StateType.RepeatPuk:
      let disable = self.controller.getPUK().len == PUKLengthForStatusApp
      self.view.setDisablePopup(disable)
      return
  self.view.setDisablePopup(true)

proc preStateActivities[T](self: Module[T], currFlowType: FlowType, nextStateType: StateType) =
  if nextStateType == StateType.MaxPinRetriesReached or
    nextStateType == StateType.MaxPukRetriesReached or
    nextStateType == StateType.MaxPairingSlotsReached or
    nextStateType == StateType.UnlockKeycardOptions:
      ## in case the card is locked on another device, we're updating its state in the DB
      let (_, flowEvent) = self.controller.getLastReceivedKeycardData()
      self.controller.setCurrentKeycardStateToLocked(flowEvent.keyUid, flowEvent.instanceUID)

  if currFlowType == FlowType.Authentication:
    self.view.setLockedPropForKeyPairForProcessing(nextStateType == StateType.MaxPinRetriesReached)

  if currFlowType == FlowType.UnlockKeycard:
    if nextStateType == StateType.UnlockKeycardOptions:
      let (_, flowEvent) = self.controller.getLastReceivedKeycardData()
      let offerPuk = flowEvent.pukRetries > 0
      self.controller.setKeycardData(updatePredefinedKeycardData(self.controller.getKeycardData(), PredefinedKeycardData.OfferPukForUnlock, add = offerPuk))

proc reEvaluateKeyPairForProcessing[T](self: Module[T], currFlowType: FlowType, currStateType: StateType) =
  if currFlowType == FlowType.UnlockKeycard or
    currFlowType == FlowType.RenameKeycard or
    currFlowType == FlowType.ChangeKeycardPin or
    currFlowType == FlowType.ChangeKeycardPuk or
    currFlowType == FlowType.ChangePairingCode or
    currFlowType == FlowType.CreateCopyOfAKeycard:
      if currStateType != StateType.PluginReader and 
        currStateType != StateType.ReadingKeycard:
          return
      let (_, flowEvent) = self.controller.getLastReceivedKeycardData()
      var keycardUid = ""
      if self.getKeyPairForProcessing().getKeyUid() == flowEvent.keyUid:
        keycardUid = flowEvent.instanceUID
      self.prepareKeyPairForProcessing(self.getKeyPairForProcessing().getKeyUid(), keycardUid)

proc handleKeycardSyncing[T](self: Module[T]) =
  if not self.controller.keycardSyncingInProgress():
    return
  let kcsFlowType = self.controller.getCurrentKeycardServiceFlow()
  if kcsFlowType == KCSFlowType.GetMetadata:
    let (eventType, flowEvent) = self.controller.getLastReceivedKeycardData()
    if flowEvent.keyUid != self.controller.getKeyUidWhichIsBeingSyncing():
      self.controller.terminateCurrentFlow(lastStepInTheCurrentFlow = false)
      return
    if eventType == ResponseTypeValueKeycardFlowResult and flowEvent.error.len == 0:
      var kpDto = KeyPairDto(keycardUid: flowEvent.instanceUID,
        keycardName: flowEvent.cardMetadata.name,
        keycardLocked: false,
        accountsAddresses: @[],
        keyUid: flowEvent.keyUid)
      let alreadySetKeycards = self.controller.getAllKnownKeycards().filter(kp => kp.keycardUid == flowEvent.instanceUID)
      if alreadySetKeycards.len == 1:
        var accountsToRemove = alreadySetKeycards[0].accountsAddresses
        let appAccounts = self.controller.getWalletAccounts()
        var activeValidPathsToStoreToAKeycard: seq[string]
        for appAcc in appAccounts:
          if appAcc.keyUid != flowEvent.keyUid:
            continue
          activeValidPathsToStoreToAKeycard.add(appAcc.path)
          var index = -1
          var found = false
          for acc in accountsToRemove:
            index.inc
            if cmpIgnoreCase(acc, appAcc.address) == 0:
              found = true
              break
          if found and index > -1:
            # if account address which is present in the wallet is still present in accounts addresses of a keycard, 
            # then it needs to be present in `keypairs` table in db, so remove it from the list
            accountsToRemove.delete(index)
          else:
            # we store to db only accounts we haven't stored before, accounts which are already on a keycard (in metadata)
            # we assume they are already in the db
            kpDto.accountsAddresses.add(appAcc.address)
        if accountsToRemove.len > 0:
          self.controller.removeMigratedAccountsForKeycard(kpDto.keyUid, kpDto.keycardUid, accountsToRemove)
        if kpDto.accountsAddresses.len > 0:
          self.controller.addMigratedKeyPair(kpDto)
        # if all accounts are removed from the app, there is no point in storing empty accounts list to a keycard, cause in that case
        # keypair which is on that keycard won't be known to the app, that means keypair was removed from the app
        if activeValidPathsToStoreToAKeycard.len > 0:
          ##  we need to store paths to a keycard if the num of paths in the app and on a keycard is diffrent
          ## or if the paths are different
          var storeToKeycard = activeValidPathsToStoreToAKeycard.len != flowEvent.cardMetadata.walletAccounts.len
          if not storeToKeycard:
            for wa in flowEvent.cardMetadata.walletAccounts:
              if not utils.arrayContains(activeValidPathsToStoreToAKeycard, wa.path):
                storeToKeycard = true
                break
          if storeToKeycard:
            self.controller.runStoreMetadataFlow(flowEvent.cardMetadata.name, self.controller.getPin(), activeValidPathsToStoreToAKeycard)
            return
      elif alreadySetKeycards.len > 1:
        error "it's impossible to have more then one keycard with the same uid", keycarUid=flowEvent.instanceUID
  self.controller.terminateCurrentFlow(lastStepInTheCurrentFlow = true)

method syncKeycardBasedOnAppState*[T](self: Module[T], keyUid: string, pin: string) =
  ## This method must not be called directly. If you want to initiate keycard syncing please emit
  ## `SIGNAL_SHARED_KEYCARD_MODULE_TRY_KEYCARD_SYNC` signal
  if pin.len != PINLengthForStatusApp:
    debug "cannot sync with the pin which doesn't meet app expectations"
    return
  if keyUid.len == 0:
    debug "cannot sync with the empty keyUid"
    return
  self.init()
  self.controller.setKeyUidWhichIsBeingSyncing(keyUid)
  self.controller.setPin(pin)
  self.controller.setKeycardSyncingInProgress(true)
  self.controller.runGetMetadataFlow(resolveAddress = true, exportMasterAddr = true, pin)

method onBackActionClicked*[T](self: Module[T]) =
  let currStateObj = self.view.currentStateObj()
  if currStateObj.isNil:
    error "sm_cannot resolve current state"
    return
  debug "sm_back_action", currFlow=currStateObj.flowType(), currState=currStateObj.stateType()
  self.preActionActivities(currStateObj.flowType(), currStateObj.stateType())
  currStateObj.executePreBackStateCommand(self.controller)
  let backState = currStateObj.getBackState()
  self.preStateActivities(backState.flowType(), backState.stateType())
  self.view.setCurrentState(backState)
  currStateObj.executePostBackStateCommand(self.controller)
  debug "sm_back_action - set state", setCurrFlow=backState.flowType(), newCurrState=backState.stateType()
  currStateObj.delete()

method onCancelActionClicked*[T](self: Module[T]) =
  let currStateObj = self.view.currentStateObj()
  if currStateObj.isNil:
    error "sm_cannot resolve current state"
    return
  debug "sm_cancel_action", currFlow=currStateObj.flowType(), currState=currStateObj.stateType()
  self.preActionActivities(currStateObj.flowType(), currStateObj.stateType())
  currStateObj.executeCancelCommand(self.controller)
    
method onPrimaryActionClicked*[T](self: Module[T]) =
  let currStateObj = self.view.currentStateObj()
  if currStateObj.isNil:
    error "sm_cannot resolve current state"
    return
  debug "sm_primary_action", currFlow=currStateObj.flowType(), currState=currStateObj.stateType()
  self.preActionActivities(currStateObj.flowType(), currStateObj.stateType())
  currStateObj.executePrePrimaryStateCommand(self.controller)
  let nextState = currStateObj.getNextPrimaryState(self.controller)
  if nextState.isNil:
    return
  self.preStateActivities(nextState.flowType(), nextState.stateType())
  self.reEvaluateKeyPairForProcessing(currStateObj.flowType(), currStateObj.stateType())
  self.view.setCurrentState(nextState)
  currStateObj.executePostPrimaryStateCommand(self.controller)
  debug "sm_primary_action - set state", setCurrFlow=nextState.flowType(), setCurrState=nextState.stateType()

method onSecondaryActionClicked*[T](self: Module[T]) =
  let currStateObj = self.view.currentStateObj()
  if currStateObj.isNil:
    error "sm_cannot resolve current state"
    return
  debug "sm_secondary_action", currFlow=currStateObj.flowType(), currState=currStateObj.stateType()
  self.preActionActivities(currStateObj.flowType(), currStateObj.stateType())
  currStateObj.executePreSecondaryStateCommand(self.controller)
  let nextState = currStateObj.getNextSecondaryState(self.controller)
  if nextState.isNil:
    return
  self.preStateActivities(nextState.flowType(), nextState.stateType())
  self.reEvaluateKeyPairForProcessing(currStateObj.flowType(), currStateObj.stateType())
  self.view.setCurrentState(nextState)
  currStateObj.executePostSecondaryStateCommand(self.controller)
  debug "sm_secondary_action - set state", setCurrFlow=nextState.flowType(), setCurrState=nextState.stateType()

method onKeycardResponse*[T](self: Module[T], keycardFlowType: string, keycardEvent: KeycardEvent) =
  if self.controller.keycardSyncingInProgress():
    self.handleKeycardSyncing()
    return
  if self.derivingAccountDetails.deriveAddressAfterAuthentication and
    self.derivingAccountDetails.addressRequested:
      # clearing...
      self.derivingAccountDetails = DerivingAccountDetails()
      # notify about generated address
      self.controller.notifyAboutGeneratedWalletAccount(keycardEvent.generatedWalletAccount, keycardEvent.masterKeyAddress)
      return
  ## Check local state first, in case postponed flow is run
  if not self.tmpLocalState.isNil:
    let nextState = self.tmpLocalState.resolveKeycardNextState(keycardFlowType, keycardEvent, self.controller)
    defer: self.tmpLocalState.delete
    defer: self.tmpLocalState = nil
    if nextState.isNil:
      return
    self.preStateActivities(nextState.flowType(), nextState.stateType())
    self.reEvaluateKeyPairForProcessing(self.tmpLocalState.flowType(), self.tmpLocalState.stateType())
    self.view.setCurrentState(nextState)
    self.controller.readyToDisplayPopup()
    debug "sm_on_keycard_response - from_local - set state", setCurrFlow=nextState.flowType(), setCurrState=nextState.stateType()
    return
  ## Check regular flows
  let currStateObj = self.view.currentStateObj()
  if currStateObj.isNil:
    return
  debug "sm_on_keycard_response", currFlow=currStateObj.flowType(), currState=currStateObj.stateType()
  let nextState = currStateObj.resolveKeycardNextState(keycardFlowType, keycardEvent, self.controller)
  if nextState.isNil:
    return
  self.preStateActivities(nextState.flowType(), nextState.stateType())
  self.reEvaluateKeyPairForProcessing(currStateObj.flowType(), currStateObj.stateType())
  self.view.setCurrentState(nextState)
  debug "sm_on_keycard_response - set state", setCurrFlow=nextState.flowType(), setCurrState=nextState.stateType()

proc buildKeyPairsList[T](self: Module[T], excludeAlreadyMigratedPairs: bool): seq[KeyPairItem] =
  let keyPairMigrated = proc(keyUid: string): bool =
    result = false
    let migratedKeyPairs = self.controller.getAllMigratedKeyPairs()
    for kp in migratedKeyPairs:
      if kp.keyUid == keyUid:
        return true

  let countOfKeyPairsForType = proc(items: seq[KeyPairItem], keyPairType: KeyPairType): int =
    result = 0
    for i in 0 ..< items.len:
      if(items[i].getPairType() == keyPairType.int):
        result.inc

  let accounts = self.controller.getWalletAccounts()
  var items: seq[KeyPairItem]
  for a in accounts:
    if a.isChat or a.walletType == WalletTypeWatch or (excludeAlreadyMigratedPairs and keyPairMigrated(a.keyUid)):
      continue
    if a.walletType == WalletTypeDefaultStatusAccount:
      var item = newKeyPairItem(keyUid = a.keyUid,
        pubKey = a.publicKey,
        locked = false,
        name = singletonInstance.userProfile.getName(),
        image = singletonInstance.userProfile.getIcon(),
        icon = "",
        pairType = KeyPairType.Profile,
        derivedFrom = a.derivedfrom)
      for ga in accounts:
        if cmpIgnoreCase(ga.derivedfrom, a.derivedfrom) != 0:
          continue
        var icon = ""
        if a.walletType == WalletTypeDefaultStatusAccount:
          icon = "wallet"
        item.addAccount(newKeyPairAccountItem(ga.name, ga.path, ga.address, ga.publicKey, ga.emoji, ga.color, icon, balance = 0.0))
      items.insert(item, 0) # Status Account must be at first place
      continue
    if a.walletType == WalletTypeSeed:
      let diffImports = countOfKeyPairsForType(items, KeyPairType.SeedImport)
      var item = newKeyPairItem(keyUid = a.keyUid,
        pubKey = a.publicKey,
        locked = false,
        name = "Seed Phrase " & $(diffImports + 1), # string created here should be transalted, but so far it's like it is
        image = "",
        icon = "key_pair_seed_phrase",
        pairType = KeyPairType.SeedImport,
        derivedFrom = a.derivedfrom)
      for ga in accounts:
        if cmpIgnoreCase(ga.derivedfrom, a.derivedfrom) != 0:
          continue
        item.addAccount(newKeyPairAccountItem(ga.name, ga.path, ga.address, ga.publicKey, ga.emoji, ga.color, icon = "", balance = 0.0))
      items.add(item)
      continue
    if a.walletType == WalletTypeKey:
      let diffImports = countOfKeyPairsForType(items, KeyPairType.PrivateKeyImport)
      var item = newKeyPairItem(keyUid = a.keyUid,
        pubKey = a.publicKey,
        locked = false,
        name = "Key " & $(diffImports + 1), # string created here should be transalted, but so far it's like it is
        image = "",
        icon = "key_pair_private_key",
        pairType = KeyPairType.PrivateKeyImport,
        derivedFrom = a.derivedfrom)
      item.addAccount(newKeyPairAccountItem(a.name, a.path, a.address, a.publicKey, a.emoji, a.color, icon = "", balance = 0.0))
      items.add(item)
      continue
  if items.len == 0:
    debug "sm_there is no any key pair for the logged in user that is not already migrated to a keycard"
  return items

proc prepareKeyPairItemForAuthentication[T](self: Module[T], keyUid: string) =
  var item = newKeyPairItem()
  let items = self.buildKeyPairsList(excludeAlreadyMigratedPairs = false)
  for it in items:
    if it.getKeyUid() == keyUid:
      item = it
      break
  if item.getName().len == 0:
    error "sm_cannot find keypair among known keypairs for the given keyUid for authentication", keyUid=keyUid
  item.setPubKey("")
  item.setImage("")
  item.setIcon("keycard")
  item.setPairType(KeyPairType.Unknown.int)
  self.view.setKeyPairForProcessing(item)

method setKeyPairForProcessing*[T](self: Module[T], item: KeyPairItem) =
  if item.isNil:
    error "keypair item must not be nil"
    return
  self.view.setKeyPairForProcessing(item)

method prepareKeyPairForProcessing*[T](self: Module[T], keyUid: string, keycardUid = "") =
  var item = newKeyPairItem()
  let items = self.buildKeyPairsList(excludeAlreadyMigratedPairs = false)
  for it in items:
    if it.getKeyUid() == keyUid:
      item = it
      break
  if item.getName().len == 0:
    error "sm_cannot find keypair among known keypairs for the given keyUid for processing", keyUid=keyUid
  if keycardUid.len > 0:
    let keyPairs = self.controller.getAllKnownKeycards()
    for kp in keyPairs:
      if kp.keycardUid == keycardUid:
        item.setLocked(kp.keycardLocked)
  if item.getPairType() != KeyPairType.Profile.int:
    item.setIcon("keycard")
  self.view.setKeyPairForProcessing(item)

method runFlow*[T](self: Module[T], flowToRun: FlowType, keyUid = "", bip44Path = "", txHash = "") =
  ## In case of `Authentication` if we're signing a transaction we need to provide a key uid of a keypair that an account 
  ## we want to sign a transaction for belongs to. If we're just doing an authentication for a logged in user, then 
  ## default key uid is always the key uid of the logged in user.
  if flowToRun == FlowType.General:
    self.controller.terminateCurrentFlow(lastStepInTheCurrentFlow = false)
    error "sm_cannot run an general flow"
    return
  self.init()
  if flowToRun == FlowType.FactoryReset:
    self.tmpLocalState = newReadingKeycardState(flowToRun, nil)
    self.controller.runGetMetadataFlow(resolveAddress = true)
    return
  if flowToRun == FlowType.SetupNewKeycard:
    let items = self.buildKeyPairsList(excludeAlreadyMigratedPairs = true)
    self.view.createKeyPairModel(items)
    self.view.setCurrentState(newSelectExistingKeyPairState(flowToRun, nil))
    self.controller.readyToDisplayPopup()
    return
  if flowToRun == FlowType.Authentication:
    self.controller.connectKeychainSignals()
    if keyUid.len > 0:
      self.prepareKeyPairItemForAuthentication(keyUid)
      self.tmpLocalState = newReadingKeycardState(flowToRun, nil)
      self.controller.runAuthenticationFlow(keyUid)
      return
    if singletonInstance.userProfile.getUsingBiometricLogin():
      self.controller.tryToObtainDataFromKeychain()
      return
    self.view.setCurrentState(newEnterPasswordState(flowToRun, nil))
    self.authenticationPopupIsAlreadyRunning = true
    self.controller.readyToDisplayPopup()
    return
  if flowToRun == FlowType.UnlockKeycard:
    ## since we can run unlock keycard flow from an already running flow, in order to avoid changing displayed keypair
    ## (locked keypair) we have to set keycard uid of a keycard used in the flow we're jumping from to `UnlockKeycard` flow.
    self.prepareKeyPairForProcessing(keyUid, self.controller.getKeycardUid())
    self.tmpLocalState = newReadingKeycardState(flowToRun, nil)
    self.controller.runGetMetadataFlow(resolveAddress = true)
    return
  if flowToRun == FlowType.DisplayKeycardContent:
    self.tmpLocalState = newReadingKeycardState(flowToRun, nil)
    self.controller.runGetMetadataFlow(resolveAddress = true)
    return
  if flowToRun == FlowType.RenameKeycard:
    self.prepareKeyPairForProcessing(keyUid)
    self.tmpLocalState = newReadingKeycardState(flowToRun, nil)
    self.controller.runGetMetadataFlow(resolveAddress = true) # we're firstly displaying the keycard content
    return
  if flowToRun == FlowType.ChangeKeycardPin:
    self.prepareKeyPairForProcessing(keyUid)
    self.tmpLocalState = newReadingKeycardState(flowToRun, nil)
    self.controller.runChangePinFlow()
    return
  if flowToRun == FlowType.ChangeKeycardPuk:
    self.prepareKeyPairForProcessing(keyUid)
    self.tmpLocalState = newReadingKeycardState(flowToRun, nil)
    self.controller.runChangePukFlow()
    return
  if flowToRun == FlowType.ChangePairingCode:
    self.prepareKeyPairForProcessing(keyUid)
    self.tmpLocalState = newReadingKeycardState(flowToRun, nil)
    self.controller.runChangePairingFlow()
    return
  if flowToRun == FlowType.AuthenticateAndDeriveAccountAddress:
    self.prepareKeyPairForProcessing(keyUid) ## needed for keycard sync
    self.derivingAccountDetails = DerivingAccountDetails(
      keyUid: keyUid,
      path: bip44Path,
      deriveAddressAfterAuthentication: true,
      addressRequested: false
    )
    self.controller.authenticateUser(keyUid)
    return
  if flowToRun == FlowType.CreateCopyOfAKeycard:
    self.prepareKeyPairForProcessing(keyUid)
    self.tmpLocalState = newReadingKeycardState(flowToRun, nil)
    self.controller.runGetMetadataFlow(resolveAddress = true)
    return
  if flowToRun == FlowType.SetupNewKeycardNewSeedPhrase:
    self.tmpLocalState = newReadingKeycardState(flowToRun, nil)
    self.controller.runLoadAccountFlow()
    return
  if flowToRun == FlowType.SetupNewKeycardOldSeedPhrase:
    self.tmpLocalState = newReadingKeycardState(flowToRun, nil)
    self.controller.runLoadAccountFlow()
    return
  if flowToRun == FlowType.ImportFromKeycard:
    self.tmpLocalState = newReadingKeycardState(flowToRun, nil)
    self.controller.runGetMetadataFlow(resolveAddress = true, exportMasterAddr = true)
    return

method setSelectedKeyPair*[T](self: Module[T], item: KeyPairItem) =
  var paths: seq[string]
  var keyPairDto = KeyPairDto(keycardUid: "", # will be set during migration
    keycardName: item.getName(),
    keycardLocked: item.getLocked(),
    keyUid: item.getKeyUid())
  for a in item.getAccountsModel().getItems():
    paths.add(a.getPath())
    keyPairDto.accountsAddresses.add(a.getAddress())
  self.controller.setSelectedKeyPair(isProfile = item.getPairType() == KeyPairType.Profile.int,
    paths, keyPairDto)
  self.setKeyPairForProcessing(item)

proc generateRandomColor[T](self: Module[T]): string = 
  let r = rand(0 .. 255)
  let g = rand(0 .. 255)
  let b = rand(0 .. 255)
  return "#" & r.toHex(2) & g.toHex(2) & b.toHex(2) 

proc updateKeyPairItemIfDataAreKnown[T](self: Module[T], address: string, item: var KeyPairItem): bool =
  let accounts = self.controller.getWalletAccounts()
  for a in accounts:
    if a.isChat or a.walletType == WalletTypeWatch or cmpIgnoreCase(a.address, address) != 0:
      continue
    var icon = ""
    if a.walletType == WalletTypeDefaultStatusAccount:
      icon = "wallet"
    item.setKeyUid(a.keyUid)
    item.addAccount(newKeyPairAccountItem(a.name, a.path, a.address, a.publicKey, a.emoji, a.color, icon, balance = 0.0))
    return true
  return false

proc buildKeyPairItemBasedOnCardMetadata[T](self: Module[T], cardMetadata: CardMetadata): 
  tuple[item: KeyPairItem, knownKeyPair: bool] =
  result.item = newKeyPairItem(keyUid = "",
    pubKey = "",
    locked = false,
    name = cardMetadata.name,
    image = "",
    icon = "keycard",
    pairType = KeyPairType.Unknown,
    derivedFrom = "")
  let currKp = self.getKeyPairForProcessing()
  if not currKp.isNil:
    result.item.setKeyUid(currKp.getKeyUid())
    result.item.setPubKey(currKp.getPubKey())
  result.knownKeyPair = true
  for wa in cardMetadata.walletAccounts:
    if self.updateKeyPairItemIfDataAreKnown(wa.address, result.item):
      continue
    let balance = self.controller.getCurrencyBalanceForAddress(wa.address)
    result.knownKeyPair = false
    result.item.addAccount(newKeyPairAccountItem(name = "", wa.path, wa.address, pubKey = wa.publicKey, emoji = "", color = self.generateRandomColor(), icon = "wallet", balance))

method updateKeyPairForProcessing*[T](self: Module[T], cardMetadata: CardMetadata) =
  let(item, knownKeyPair) = self.buildKeyPairItemBasedOnCardMetadata(cardMetadata)
  self.view.setKeyPairStoredOnKeycardIsKnown(knownKeyPair)
  self.view.setKeyPairForProcessing(item)

method updateKeyPairHelper*[T](self: Module[T], cardMetadata: CardMetadata) =
  let(item, knownKeyPair) = self.buildKeyPairItemBasedOnCardMetadata(cardMetadata)
  self.view.setKeyPairStoredOnKeycardIsKnown(knownKeyPair)
  self.view.setKeyPairHelper(item)

method onUserAuthenticated*[T](self: Module[T], password: string, pin: string) =
  if self.derivingAccountDetails.deriveAddressAfterAuthentication:
    self.derivingAccountDetails.addressRequested = true
    self.controller.setPassword(password)
    self.controller.setPin(pin) # we need to keep it in case new acc is added we need to sync accounts on the Keycard 
    self.controller.runDeriveAccountFlow(self.derivingAccountDetails.path, pin)
    return
  let flowType = self.getCurrentFlowType()
  if flowType == FlowType.SetupNewKeycard:
    self.controller.setPassword(password)
    self.onSecondaryActionClicked()

method keychainObtainedDataFailure*[T](self: Module[T], errorDescription: string, errorType: string) =
  let currStateObj = self.view.currentStateObj()
  if currStateObj.isNil or 
    currStateObj.stateType() == StateType.EnterPassword or 
    currStateObj.stateType() == StateType.WrongPassword or
    currStateObj.stateType() == StateType.BiometricsPasswordFailed:
      self.view.setCurrentState(newBiometricsPasswordFailedState(FlowType.Authentication, nil))
      if not self.authenticationPopupIsAlreadyRunning:
        self.authenticationPopupIsAlreadyRunning = true
        self.controller.readyToDisplayPopup()
      return
  if not currStateObj.isNil:
    self.view.setCurrentState(newBiometricsPinFailedState(FlowType.Authentication, nil))

method keychainObtainedDataSuccess*[T](self: Module[T], data: string) =
  let currStateObj = self.view.currentStateObj()
  if currStateObj.isNil or 
    currStateObj.stateType() == StateType.EnterPassword or 
    currStateObj.stateType() == StateType.WrongPassword or
    currStateObj.stateType() == StateType.BiometricsPasswordFailed:
      if self.controller.verifyPassword(data):
        self.controller.setPassword(data)
        self.controller.terminateCurrentFlow(lastStepInTheCurrentFlow = true)
      else:
        self.view.setCurrentState(newEnterBiometricsPasswordState(FlowType.Authentication, nil))
        if not self.authenticationPopupIsAlreadyRunning:
          self.authenticationPopupIsAlreadyRunning = true
          self.controller.readyToDisplayPopup()
      return
  if not currStateObj.isNil:
    if data.len == PINLengthForStatusApp:
      self.controller.enterKeycardPin(data)
    else:
      self.view.setCurrentState(newBiometricsPinInvalidState(FlowType.Authentication, nil))