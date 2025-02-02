import QtQuick 2.14

ListModel {
    id: root

    ListElement {
        pubKey: "0x043a7ed0e8d1012cf04"
        onlineStatus: 1
        isContact: true
        isVerified: true
        isAdmin: false
        isUntrustworthy: false
        displayName: "Mike"
        alias: ""
        localNickname: ""
        ensName: ""
        icon: "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAADIAAAAyCAYAAAAeP4ixAAAAlklEQVR4nOzW0QmDQBAG4SSkl7SUQlJGCrElq9F3QdjjVhh/5nv3cFhY9vUIYQiNITSG0BhCExPynn1gWf9bx498P7/
              nzPcxEzGExhBdJGYihtAYQlO+tUZvqrPbqeudo5iJGEJjCE15a3VtodH3q2ImYgiNITTlTdG1nUZ5a92VITQxITFiJmIIjSE0htAYQrMHAAD//+wwFVpz+yqXAAAAAElFTkSuQmCC"
        colorId: 7
    }
    ListElement {
        pubKey: "0x04df12f12f12f12f1234"
        onlineStatus: 0
        isContact: true
        isVerified: true
        isAdmin: false
        isUntrustworthy: false
        displayName: "Jane"
        alias: ""
        localNickname: ""
        ensName: ""
        icon: ""
        colorId: 7
    }
    ListElement {
        pubKey: "0x04d1b7cc0ef3f470f1238"
        onlineStatus: 0
        isContact: true
        isVerified: false
        isAdmin: false
        isUntrustworthy: true
        displayName: "John"
        alias: ""
        localNickname: "Johny Johny"
        ensName: ""
        icon: ""
        colorId: 7
    }
    ListElement {
        pubKey: "0x04d1bed192343f470f1255"
        onlineStatus: 1
        isContact: true
        isVerified: true
        isAdmin: false
        isUntrustworthy: true
        displayName: ""
        alias: "meth"
        localNickname: ""
        ensName: "maria.eth"
        icon: ""
        colorId: 7
    }
}
