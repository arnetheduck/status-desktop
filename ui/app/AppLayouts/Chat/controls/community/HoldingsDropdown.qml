import QtQuick 2.14
import QtQuick.Layouts 1.14

import StatusQ.Core 0.1
import StatusQ.Core.Theme 0.1
import StatusQ.Components 0.1
import StatusQ.Controls 0.1
import StatusQ.Core.Utils 0.1

import AppLayouts.Chat.helpers 1.0


StatusDropdown {
    id: root

    property var store

    property string assetKey: ""
    property real assetAmount: 0

    property string collectibleKey: ""
    property real collectibleAmount: 1
    property bool collectiblesSpecificAmount: false

    property int ensType: EnsPanel.EnsType.Any
    property string ensDomainName: ""

    signal addAsset(string key, real amount)
    signal addCollectible(string key, real amount)
    signal addEns(bool any, string customDomain)

    signal updateAsset(string key, real amount)
    signal updateCollectible(string key, real amount)
    signal updateEns(bool any, string customDomain)

    signal removeClicked

    function reset() {
        d.currentHoldingType = HoldingTypes.Type.Asset
        d.assetAmountText = ""
        d.collectibleAmountText = ""

        root.assetKey = ""
        root.collectibleKey = ""
        root.assetAmount = 0
        root.collectibleAmount = 1
        root.collectiblesSpecificAmount = false
        root.ensType = EnsPanel.EnsType.Any
        root.ensDomainName = ""

        statesStack.clear()
    }

    width: d.defaultWidth
    padding: d.padding

    // force keeping within the bounds of the enclosing window
    margins: 0

    onClosed: root.reset()

    enum FlowType {
        Add, Update
    }

    function openFlow(flowType) {
        switch (flowType) {
            case HoldingsDropdown.FlowType.Add:
                statesStack.push(d.addState)
                break
            case HoldingsDropdown.FlowType.Update:
                statesStack.push(d.updateState)
                break
            default:
                console.warn("Unknown flow type.")
                return
        }

        open()
    }

    function setActiveTab(holdingType) {
        d.currentHoldingType = holdingType
    }

    QtObject {
        id: d

        // Internal management properties and signals:
        readonly property bool assetsReady: root.assetAmount > 0 && root.assetKey
        readonly property bool collectiblesReady: root.collectibleAmount > 0 && root.collectibleKey
        readonly property bool ensReady: root.ensType === EnsPanel.EnsType.Any || d.ensDomainNameValid

        readonly property string addState: "ADD"
        readonly property string updateState: "UPDATE"
        readonly property string extendedState: "EXTENDED"

        property int holdingsTabMode: HoldingsTabs.Mode.Add
        property int extendedDropdownType: ExtendedDropdownContent.Type.Assets

        property string assetAmountText: ""
        property string collectibleAmountText: ""

        property int currentHoldingType: HoldingTypes.Type.Asset

        property bool ensDomainNameValid: false

        signal addClicked
        signal updateClicked

        // By design values:
        readonly property int padding: 8

        readonly property int defaultWidth: 289
        readonly property int extendedContentHeight: 380

        readonly property int tabsAddModeBaseHeight: 232 - padding * 2
        readonly property int tabsAddModeExtendedHeight: 277 - padding * 2

        readonly property int tabsUpdateModeBaseHeight: 284 - padding * 2
        readonly property int tabsUpdateModeExtendedHeight: tabsUpdateModeBaseHeight
                                                            + (tabsAddModeExtendedHeight - tabsAddModeBaseHeight)

        readonly property int backButtonWidth: 56
        readonly property int backButtonHeight: 24
        readonly property int backButtonToContentSpace: 8

        readonly property string defaultAssetNameText: qsTr("Choose asset")
        readonly property string defaultCollectibleNameText: qsTr("Choose collectible")
    }

    QtObject {
        id: statesStack

        property alias currentState: content.state
        property int size: 0
        property var states: []

        function push(state) {
            states.push(state)
            currentState = state
            size++
        }

        function pop() {
            states.pop()
            currentState = states.length ? states[states.length - 1] : ""
            size--
        }

        function clear() {
            currentState = ""
            size = 0
            states = []
        }
    }

    contentItem: ColumnLayout {
        id: content

        spacing: d.backButtonToContentSpace

        StatusIconTextButton {
            id: backButton

            Layout.preferredWidth: d.backButtonWidth
            Layout.preferredHeight: d.backButtonHeight

            visible: statesStack.size > 1

            spacing: 0
            leftPadding: 4
            statusIcon: "next"
            icon.width: 12
            icon.height: 12
            iconRotation: 180
            text: qsTr("Back")
        }

        Loader {
            id: loader
            Layout.fillWidth: true
            Layout.fillHeight: true
        }

        states: [
            State {
                name: d.addState
                PropertyChanges {target: loader; sourceComponent: tabsView}
                PropertyChanges {target: root; height: undefined} // use implicit height
            },
            State {
                name: d.updateState
                extend: d.addState
                PropertyChanges {target: d; holdingsTabMode: HoldingsTabs.Mode.Update}
            },
            State {
                name: d.extendedState
                PropertyChanges {target: loader; sourceComponent: extendedView}
                PropertyChanges {target: root; height: d.extendedContentHeight}
            }
        ]
    }

    Component {
        id: tabsView

        HoldingsTabs {
            id: holdingsTabs

            readonly property var holdingTypes: [
                HoldingTypes.Type.Asset, HoldingTypes.Type.Collectible, HoldingTypes.Type.Ens
            ]
            readonly property var labels: [qsTr("Asset"), qsTr("Collectible"), qsTr("ENS")]

            readonly property bool extendedHeight:
                d.currentHoldingType === HoldingTypes.Type.Collectible && collectiblesSpecificAmount ||
                d.currentHoldingType === HoldingTypes.Type.Ens && root.ensType === EnsPanel.EnsType.CustomSubdomain

            implicitHeight: extendedHeight
                            ? (mode === HoldingsTabs.Mode.Add ? d.tabsAddModeExtendedHeight : d.tabsUpdateModeExtendedHeight)
                            : (mode === HoldingsTabs.Mode.Add ? d.tabsAddModeBaseHeight : d.tabsUpdateModeBaseHeight)

            states: [
                State {
                    name: HoldingTypes.Type.Asset
                    PropertyChanges {target: holdingsTabs; sourceComponent: assetsLayout; addOrUpdateButtonEnabled: d.assetsReady}
                },
                State {
                    name: HoldingTypes.Type.Collectible
                    PropertyChanges {target: holdingsTabs; sourceComponent: collectiblesLayout; addOrUpdateButtonEnabled: d.collectiblesReady}
                },
                State {
                    name: HoldingTypes.Type.Ens
                    PropertyChanges {target: holdingsTabs; sourceComponent: ensLayout; addOrUpdateButtonEnabled: d.ensReady}
                }
            ]

            tabLabels: labels
            state: d.currentHoldingType
            mode: d.holdingsTabMode

            currentIndex: holdingTypes.indexOf(d.currentHoldingType)
            onCurrentIndexChanged: d.currentHoldingType = holdingTypes[currentIndex]

            onAddClicked: d.addClicked()
            onUpdateClicked: d.updateClicked()
            onRemoveClicked: root.removeClicked()

            Connections {
                target: backButton

                function onClicked() {
                    statesStack.pop()
                }
            }
        }
    }

    Component {
        id: assetsLayout

        AssetsPanel {
            id: assetsPanel

            assetName: d.defaultAssetNameText
            amountText: d.assetAmountText
            onAmountTextChanged: d.assetAmountText = amountText

            readonly property real effectiveAmount: amountValid ? amount : 0
            onEffectiveAmountChanged: root.assetAmount = effectiveAmount

            onPickerClicked: {
                d.extendedDropdownType = ExtendedDropdownContent.Type.Assets
                statesStack.push(d.extendedState)
            }

            readonly property string assetKey: root.assetKey

            onAssetKeyChanged: {
                const modelItem = CommunityPermissionsHelpers.getAssetByKey(
                                    store.assetsModel, assetKey)

                if (modelItem) {
                    assetsPanel.assetName = modelItem.shortName
                    assetsPanel.assetImage = modelItem.iconSource
                } else {
                    assetsPanel.assetName = d.defaultAssetNameText
                    assetsPanel.assetImage = ""
                }
            }

            Component.onCompleted: {
                if (d.assetAmountText.length === 0 && root.assetAmount)
                    assetsPanel.setAmount(root.assetAmount)
            }

            Connections {
                target: d

                function onAddClicked() {
                    root.addAsset(root.assetKey, root.assetAmount)
                }

                function onUpdateClicked() {
                    root.updateAsset(root.assetKey, root.assetAmount)
                }
            }
        }
    }

    Component {
        id: collectiblesLayout

        CollectiblesPanel {
            id: collectiblesPanel

            collectibleName: d.defaultCollectibleNameText
            amountText: d.collectibleAmountText
            onAmountTextChanged: d.collectibleAmountText = amountText

            readonly property real effectiveAmount: amountValid ? amount : 0
            onEffectiveAmountChanged: root.collectibleAmount = effectiveAmount

            specificAmount: root.collectiblesSpecificAmount
            onSpecificAmountChanged: root.collectiblesSpecificAmount = specificAmount

            onPickerClicked: {
                d.extendedDropdownType = ExtendedDropdownContent.Type.Collectibles
                statesStack.push(d.extendedState)
            }

            Component.onCompleted: {
                if (d.collectibleAmountText.length === 0 && root.collectibleAmount)
                    collectiblesPanel.setAmount(root.collectibleAmount)
            }

            function getAmount() {
                return specificAmount ? effectiveAmount : 1
            }

            Connections {
                target: d

                function onAddClicked() {
                    root.addCollectible(root.collectibleKey, collectiblesPanel.getAmount())
                }

                function onUpdateClicked() {
                    root.updateCollectible(root.collectibleKey, collectiblesPanel.getAmount())
                }
            }

            readonly property string collectibleKey: root.collectibleKey

            onCollectibleKeyChanged: {
                const modelItem = CommunityPermissionsHelpers.getCollectibleByKey(
                                    store.collectiblesModel, collectibleKey)

                if (modelItem) {
                    collectiblesPanel.collectibleName = modelItem.name
                    collectiblesPanel.collectibleImage = modelItem.iconSource
                } else {
                    collectiblesPanel.collectibleName = d.defaultCollectibleNameText
                    collectiblesPanel.collectibleImage = ""
                }
            }
        }
    }

    Component {
        id: ensLayout

        EnsPanel {
            ensType: root.ensType
            onEnsTypeChanged: root.ensType = ensType

            domainName: root.ensDomainName
            onDomainNameChanged: root.ensDomainName = domainName
            onDomainNameValidChanged: d.ensDomainNameValid = domainNameValid

            Connections {
                target: d

                function onAddClicked() {
                    root.addEns(root.ensType === EnsPanel.EnsType.Any, root.ensDomainName)
                }

                function onUpdateClicked() {
                    root.updateEns(root.ensType === EnsPanel.EnsType.Any, root.ensDomainName)
                }
            }
        }
    }

    Component {
        id: extendedView

        ExtendedDropdownContent {
            id: extendedDropdown

            store: root.store
            type: d.extendedDropdownType

            onItemClicked: {
                statesStack.pop()

                if(d.extendedDropdownType === ExtendedDropdownContent.Type.Assets)
                    root.assetKey = key
                else
                    root.collectibleKey = key
            }

            Connections {
                target: backButton

                function onClicked() {
                    if (extendedDropdown.canGoBack)
                        extendedDropdown.goBack()
                    else
                        statesStack.pop()
                }
            }
        }
    }
}
