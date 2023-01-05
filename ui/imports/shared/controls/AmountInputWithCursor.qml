import QtQuick 2.14
import QtQuick.Controls 2.14

import StatusQ.Controls 0.1
import StatusQ.Core 0.1
import StatusQ.Core.Theme 0.1

import utils 1.0

StatusInput {
    id: cursorInput

    property string cursorColor: Theme.palette.primaryColor1

    leftPadding: 0
    rightPadding: 0
    topPadding: 0
    bottomPadding: 0

    placeholderText: ""
    input.edit.objectName: "amountInput"
    input.edit.cursorVisible: true
    input.edit.font.pixelSize: Utils.getFontSizeBasedOnLetterCount(text)
    input.placeholderFont.pixelSize: 34
    input.edit.padding: 0
    input.background.color: "transparent"
    input.background.border.width: 0
    // To-do this needs to be removed once https://github.com/status-im/StatusQ/issues/578 is implemented and cursor is moved to StatusInput
    input.edit.cursorDelegate: Rectangle {
        id: cursor
        visible: input.edit.cursorVisible
        color: cursorColor
        width: 2

        SequentialAnimation {
            loops: Animation.Infinite
            running: input.edit.cursorVisible

            PropertyAction {
                target: cursor
                property: 'visible'
                value: true
            }

            PauseAnimation {
                duration: 600
            }

            PropertyAction {
                target: cursor
                property: 'visible'
                value: false
            }

            PauseAnimation {
                duration: 600
            }

            onStopped: {
                cursor.visible = false
            }
        }
    }
}
