import QtQuick 2.14
import QtQuick.Controls 2.14
import QtQuick.Layouts 1.14

import Qt.labs.settings 1.0

import StatusQ.Core.Theme 0.1
import Storybook 1.0

ApplicationWindow {
    id: root

    width: 1450
    height: 840
    visible: true

    property string currentPage

    font.pixelSize: 13

    PagesModel {
        id: pagesModel
    }

    FigmaLinksSource {
        id: figmaLinksSource

        filePath: "figma.json"
    }

    FigmaDecoratorModel {
        id: figmaModel

        sourceModel: pagesModel
        figmaLinks: figmaLinksSource.figmaLinks
    }

    HotReloader {
        id: reloader

        loader: viewLoader
        enabled: hotReloaderControls.enabled
        onReloaded: hotReloaderControls.notifyReload()
    }

    SplitView {
        anchors.fill: parent

        Pane {
            SplitView.preferredWidth: 270

            ColumnLayout {
                width: parent.width
                height: parent.height

                Button {
                    Layout.fillWidth: true

                    text: "Settings"

                    onClicked: settingsPopup.open()
                }

                CheckBox {
                    id: darkModeCheckBox

                    Layout.fillWidth: true

                    text: "Dark mode"

                    StatusLightTheme { id: lightTheme }
                    StatusDarkTheme { id: darkTheme }

                    Binding {
                        target: Theme
                        property: "palette"
                        value: darkModeCheckBox.checked ? darkTheme : lightTheme
                    }
                }

                HotReloaderControls {
                    id: hotReloaderControls

                    Layout.fillWidth: true

                    onForceReloadClicked: reloader.forceReload()
                }

                MenuSeparator {
                    Layout.fillWidth: true
                }

                FilteredPagesList {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    currentPage: root.currentPage
                    model: pagesModel

                    onPageSelected: root.currentPage = page
                }
            }
        }

        Page {
            SplitView.fillWidth: true

            Loader {
                id: viewLoader

                anchors.fill: parent
                clip: true

                source: `pages/${root.currentPage}Page.qml`
                asynchronous: settingsLayout.loadAsynchronously
                visible: status === Loader.Ready

                // force reload when `asynchronous` changes
                onAsynchronousChanged: {
                    active = false
                    active = true
                }
            }

            BusyIndicator {
                anchors.centerIn: parent
                visible: viewLoader.status === Loader.Loading
            }

            Label {
                anchors.centerIn: parent
                visible: viewLoader.status === Loader.Error
                text: "Loading page failed"
            }

            footer: PageToolBar {
                id: pageToolBar

                title: `pages/${root.currentPage}Page.qml`
                figmaPagesCount: currentPageModelItem.object
                                 ? currentPageModelItem.object.figma.count : 0

                Instantiator {
                    id: currentPageModelItem

                    model: SingleItemProxyModel {
                        sourceModel: figmaModel
                        roleName: "title"
                        value: root.currentPage
                    }

                    delegate: QtObject {
                        readonly property string title: model.title
                        readonly property var figma: model.figma
                    }
                }

                onFigmaPreviewClicked: {
                    if (!settingsLayout.figmaToken) {
                        noFigmaTokenDialog.open()
                        return
                    }

                    figmaWindow.createObject(root, {
                        figmaModel: currentPageModelItem.object.figma,
                        pageTitle: currentPageModelItem.object.title
                    })
                }
            }
        }
    }

    Dialog {
        id: settingsPopup

        anchors.centerIn: Overlay.overlay
        width: 420
        modal: true

        header: Pane {
            background: null

            Label {
                text: "Settings"
            }
        }

        SettingsLayout {
            id: settingsLayout

            width: parent.width
        }
    }

    Dialog {
        id: noFigmaTokenDialog

        anchors.centerIn: Overlay.overlay

        title: "Figma token not set"
        standardButtons: Dialog.Ok

        Label {
            text: "Please set Figma personal token in \"Settings\""
        }
    }

    FigmaLinksCache {
        id: figmaImageLinksCache

        figmaToken: settingsLayout.figmaToken
    }

    Component {
        id: figmaWindow

        FigmaPreviewWindow {
            property string pageTitle
            property alias figmaModel: figmaImagesProxyModel.sourceModel

            title: pageTitle + " - Figma"

            model: FigmaImagesProxyModel {
                id: figmaImagesProxyModel

                figmaLinksCache: figmaImageLinksCache
            }

            onRemoveLinksRequested: figmaLinksSource.remove(pageTitle, indexes)
            onAppendLinksRequested: figmaLinksSource.append(pageTitle, links)

            onClosing: Qt.callLater(destroy)
        }
    }

    Settings {
        property alias currentPage: root.currentPage
        property alias loadAsynchronously: settingsLayout.loadAsynchronously
        property alias darkMode: darkModeCheckBox.checked
        property alias hotReloading: hotReloaderControls.enabled
        property alias figmaToken: settingsLayout.figmaToken
    }
}
