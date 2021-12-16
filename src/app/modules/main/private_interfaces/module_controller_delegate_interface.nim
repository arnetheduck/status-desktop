import ../../shared_models/section_item

method offerToStorePassword*(self: AccessInterface) {.base.} =
  raise newException(ValueError, "No implementation available")

method emitStoringPasswordError*(self: AccessInterface, errorDescription: string) {.base.} =
  raise newException(ValueError, "No implementation available")

method emitStoringPasswordSuccess*(self: AccessInterface) {.base.} =
  raise newException(ValueError, "No implementation available")

method activeSectionSet*(self: AccessInterface, sectionId: string) {.base.} =
  raise newException(ValueError, "No implementation available")

method enableSection*(self: AccessInterface, sectionType: SectionType) {.base.} =
  raise newException(ValueError, "No implementation available")

method disableSection*(self: AccessInterface, sectionType: SectionType) {.base.} =
  raise newException(ValueError, "No implementation available")

method communityJoined*(self: AccessInterface, community: CommunityDto, events: EventEmitter, contactsService: contacts_service.Service, chatService: chat_service.Service, communityService: community_service.ServiceInterface, messageService: message_service.Service) {.base.} =
  raise newException(ValueError, "No implementation available")