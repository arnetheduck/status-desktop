import ../shared_models/section_item
import ../../../app_service/service/community/service_interface as community_service

type 
  AccessInterface* {.pure inheritable.} = ref object of RootObj
  ## Abstract class for any input/interaction with this module.

method delete*(self: AccessInterface) {.base.} =
  raise newException(ValueError, "No implementation available")

method init*(self: AccessInterface) {.base.} =
  raise newException(ValueError, "No implementation available")

method getJoinedCommunities*(self: AccessInterface): seq[community_service.CommunityDto] {.base.} =
  raise newException(ValueError, "No implementation available")

method checkForStoringPassword*(self: AccessInterface) {.base.} =
  raise newException(ValueError, "No implementation available")

method storePassword*(self: AccessInterface, password: string) {.base.} =
  raise newException(ValueError, "No implementation available")

method setActiveSection*(self: AccessInterface, sectionId: string, sectionType: SectionType) {.base.} =
  raise newException(ValueError, "No implementation available")

method getNumOfNotificaitonsForChat*(self: AccessInterface): tuple[unviewed:int, mentions:int] {.base.} =
  raise newException(ValueError, "No implementation available")

method getNumOfNotificationsForCommunity*(self: AccessInterface, communityId: string): tuple[unviewed:int, mentions:int] 
  {.base.} =
  raise newException(ValueError, "No implementation available")

method setUserStatus*(self: AccessInterface, status: bool) {.base.} =
  raise newException(ValueError, "No implementation available")