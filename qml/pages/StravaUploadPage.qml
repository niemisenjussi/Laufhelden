/*
 * Copyright (C) 2017 Jussi Nieminen, Finland
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
*/

import QtQuick 2.2
import Sailfish.Silica 1.0
import com.pipacs.o2 1.0
import "../tools/SharedResources.js" as SharedResources

Page {
    id: stravaDialog
    property bool busy: false
    property string activityType: ""
    property string activityID: ""
    property var gpx
    property var uploadData;
    property alias activityName: st_name.text
    property alias activityDescription: st_description.text


    BusyIndicator {
        size: BusyIndicatorSize.Large
        anchors.centerIn: parent
        visible: parent.busy
        running: parent.busy
    }

    O2 {
        id: o2strava
        clientId: "13707"
        clientSecret: STRAVA_CLIENT_SECRET
        scope: "write"
        requestUrl: "https://www.strava.com/oauth/authorize"
        tokenUrl: "https://www.strava.com/oauth/token"
    }

    Timer {
        id: tmrStatusCheck
        running: false
        repeat: true
        interval: 2000
        onTriggered: {
            checkUploadStatus();
        }
    }

    SilicaFlickable
    {
        anchors.fill: parent
        contentHeight: input_fields.height
        contentWidth: input_fields.width

        VerticalScrollDecorator{}

        Column {
            id: input_fields
            width: stravaDialog.width

            PageHeader {
                title: "Strava Upload"
            }

            TextField {
                id: st_name
                width: parent.width
                placeholderText: qsTr("Activity name for Strava")
                label: qsTr("Name")
            }
            TextArea {
                id: st_description
                width: parent.width
                height: width * 0.6
                placeholderText: qsTr("Activity description for Strava")
                label: qsTr("Description")
            }
            TextField {
                id: st_activityType
                width: parent.width
                text: SharedResources.toStravaType(activityType)
                enabled: false
                label: qsTr("Type")
            }

            TextSwitch {
                id: chkPrivate
                text: qsTr("Private");
            }
            TextSwitch {
                id: chkCommute
                text: qsTr("Commute");
            }

            Button {
                text: "Upload"
                anchors.horizontalCenter: parent.horizontalCenter
                onClicked: {
                    busy = true;
                    uploadGPX();
                }
            }
            TextArea {
                id: lblStatus
                readOnly: true
                width: parent.width
                height: width * 0.6
            }
        }
    }

    /*
        Uploads GPX to Strava as first stage of activity upload process
    */
    function uploadGPX(){
        if (!o2strava.linked){
            console.log("Not linked to Strava");
            return;
        }

        console.log("Upload GPX...");
        statusMessage(qsTr("Uploading data..."));

        var xmlhttp = new XMLHttpRequest();
        var boundary = "--------------" + (new Date).getTime();

        xmlhttp.open("POST", "https://www.strava.com/api/v3/uploads");
        xmlhttp.setRequestHeader('Accept-Encoding', 'text');
        xmlhttp.setRequestHeader('Connection', 'keep-alive');
        xmlhttp.setRequestHeader('Pragma', 'no-cache');
        xmlhttp.setRequestHeader('Content-Type', 'multipart/form-data; boundary=' + boundary);
        xmlhttp.setRequestHeader('Cache-Control', 'no-cache');
        xmlhttp.setRequestHeader('Authorization', "Bearer " + o2strava.token);

        xmlhttp.onreadystatechange=function(){
            console.log("Ready state changed:", xmlhttp.readyState, xmlhttp.responseType, xmlhttp.responseText, xmlhttp.status, xmlhttp.statusText);
            if (xmlhttp.readyState==4 && xmlhttp.status==201){
                console.log("Post Response:", xmlhttp.responseText);
                uploadData = JSON.parse(xmlhttp.responseText);
                if (uploadData["error"] === null){
                    console.log("Upload ID:", uploadData["id"]);
                    tmrStatusCheck.start();
                    statusMessage(qsTr("Checking upload..."));
                }
                else{
                    console.log(xmlhttp.responseText);
                    console.log("GPX Import error, cannot save exercise");
                    statusMessage(uploadData["error"]);
                    busy = false;
                }
            }
            else if (xmlhttp.readyState==4 && xmlhttp.status!=201){
                busy = false;
                console.log(xmlhttp.status, xmlhttp.responseText);
                console.log("Some kind of error happened");
                var errStatus = JSON.parse(xmlhttp.responseText);
                console.log(errStatus["message"]);
                if (errStatus["message"] !== null){
                    statusMessage(errStatus["message"]);
                } else {
                    statusMessage(qsTr("An unknown error occurred"));
                }

            }
        };

        //Create a multipart form the manual way!
        var  part ="";
        part += 'Content-Disposition: form-data; name="activity_type"\r\n\r\n' + activityType + '\r\n--' + boundary + '\r\n';
        part += 'Content-Disposition: form-data; name="name"\r\n\r\n' + st_name.text + '\r\n--' + boundary + '\r\n';
        part += 'Content-Disposition: form-data; name="description"\r\n\r\n' + st_description.text + '\r\n--' + boundary + '\r\n';
        part += 'Content-Disposition: form-data; name="private"\r\n\r\n' + (chkPrivate.checked ? "1" : "0") + '\r\n--' + boundary + '\r\n';
        part += 'Content-Disposition: form-data; name="commute""\r\n\r\n' + (chkCommute.checked ? "1" : "0") + '\r\n--' + boundary + '\r\n';
        part += 'Content-Disposition: form-data; name="data_type"\r\n\r\n' + "gpx" + '\r\n--' + boundary + '\r\n';
        part += 'Content-Disposition: form-data; name="external_id"\r\n\r\n' + activityID + '\r\n--' + boundary + '\r\n';
        part += 'Content-Disposition: form-data; name="file"; filename="' + activityID + '"\r\n';
        part += "Content-Type: text/plain";
        part += "\r\n\r\n";
        part += gpx;
        part += "--" + boundary + "--" + "\r\n";

        console.log("Sending to strava...");

        xmlhttp.send(part);
    }

    function checkUploadStatus() {
        var xmlhttp = new XMLHttpRequest();

        if (!isNumeric(uploadData["id"])) {
            console.log("No upload id")
            busy = false;
            tmrStatusCheck.stop();
            return;
        }

        xmlhttp.open("GET", "https://www.strava.com/api/v3/uploads/" + uploadData.id);
        xmlhttp.setRequestHeader('Accept-Encoding', 'text');
        xmlhttp.setRequestHeader('Connection', 'keep-alive');
        xmlhttp.setRequestHeader('Pragma', 'no-cache');
        xmlhttp.setRequestHeader('Content-Type', 'application/json');
        xmlhttp.setRequestHeader('Accept', 'application/json, text/plain, */*');
        xmlhttp.setRequestHeader('Cache-Control', 'no-cache');
        xmlhttp.setRequestHeader('Authorization', "Bearer " + o2strava.token);

        xmlhttp.onreadystatechange=function(){
            console.log("Ready state changed:", xmlhttp.readyState, xmlhttp.responseType, xmlhttp.responseText, xmlhttp.status, xmlhttp.statusText);
            if (xmlhttp.readyState==4 && xmlhttp.status==200){
                console.log("Post Response:", xmlhttp.responseText);
                uploadData = JSON.parse(xmlhttp.responseText);
                if (uploadData["error"] === null){
                    console.log("Activity ID:", uploadData.activity_id);
                    if (isNumeric(uploadData.activity_id)) { //Upload is complete
                        tmrStatusCheck.stop();
                        busy = false;
                        console.log("Activity upload complete")
                        statusMessage(qsTr("Activity upload complete"));
                    }
                }
                else{
                    console.log(xmlhttp.responseText);
                    statusMessage(uploadData["error"]);
                    tmrStatusCheck.stop();
                    busy = false;
                }
            }
            else if (xmlhttp.readyState==4 && xmlhttp.status!=200){
                //console.log(xmlhttp.status, xmlhttp.responseText);
                var strerr = xmlhttp.responseText;
                console.log(strerr);
                console.log("Some kind of error happened");
                var errStatus = JSON.parse(xmlhttp.responseText);
                console.log(errStatus);
                if (errStatus.message !== null){
                    statusMessage(errStatus["message"]);
                } else {
                    statusMessage(qsTr("An unknown error occurred"));
                }
                tmrStatusCheck.stop();
                busy = false;
            }
        };

        xmlhttp.send();
    }

    function statusMessage(msg) {
        lblStatus.text = msg;
    }

    function isNumeric(n) {
        return !isNaN(parseFloat(n)) && isFinite(n);
    }
}
