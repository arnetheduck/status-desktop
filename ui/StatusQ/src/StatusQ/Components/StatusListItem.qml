import QtQuick 2.13
import StatusQ.Core 0.1
import StatusQ.Core.Theme 0.1
import StatusQ.Components 0.1
import StatusQ.Controls 0.1

Rectangle {
    id: statusListItem

    implicitWidth: 448
    implicitHeight: 64

    color: sensor.containsMouse ? Theme.palette.baseColor2 : Theme.palette.statusListItem.backgroundColor
    radius: 8

    property string title: ""
    property string subTitle: ""
    property StatusIconSettings icon: StatusIconSettings {
        height: 20
        width: 20
    }
    property StatusImageSettings image: StatusImageSettings {}
    property string label: ""

    property list<Item> components

    onComponentsChanged: {
        if (components.length) {
            for (let idx in components) {
                components[idx].parent = statusListItemComponentsSlot
            }
        }
    }

    MouseArea {
        id: sensor

        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor 
        hoverEnabled: true

        Loader {
            id: iconOrImage
            anchors.left: parent.left
            anchors.leftMargin: 16
            anchors.verticalCenter: parent.verticalCenter
            sourceComponent: !!statusListItem.icon.name ? statusRoundedIcon : statusRoundedImage
            active: !!statusListItem.icon.name || !!statusListItem.image.source.toString()
        }

        Component {
            id: statusRoundedIcon
            StatusRoundIcon {
                icon: statusListItem.icon
            }
        }

        Component {
            id: statusRoundedImage
            StatusRoundedImage {
                image.source: statusListItem.image.source
            }
        }

        Item {
            anchors.left: iconOrImage.active ? iconOrImage.right : parent.left
            anchors.leftMargin: 16
            anchors.verticalCenter: parent.verticalCenter
            height: statusListItemTitle.height + (statusListItemSubTitle.visible ? statusListItemSubTitle.height : 0)

            StatusBaseText {
                id: statusListItemTitle
                text: statusListItem.title
                font.pixelSize: 15
                color: Theme.palette.directColor1
            }

            StatusBaseText {
                id: statusListItemSubTitle
                anchors.top: statusListItemTitle.bottom

                text: statusListItem.subTitle
                font.pixelSize: 15
                color: Theme.palette.baseColor1
                visible: !!statusListItem.subTitle
            }
        }

        StatusBaseText {
            anchors.verticalCenter: parent.verticalCenter
            anchors.right: statusListItemComponentsSlot.left
            anchors.rightMargin: statusListItemComponentsSlot.width > 0 ? 10 : 0

            text: statusListItem.label
            font.pixelSize: 15
            color: Theme.palette.baseColor1
            visible: !!statusListItem.label
        }


        Row {
            id: statusListItemComponentsSlot
            anchors.right: parent.right
            anchors.rightMargin: 16
            anchors.verticalCenter: parent.verticalCenter
            spacing: 10
        }
    }
}
