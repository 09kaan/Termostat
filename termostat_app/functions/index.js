const functions = require('firebase-functions');
const admin = require('firebase-admin');
admin.initializeApp();

exports.notifyIfTempOutOfRange = functions.database
  .ref('/devices/{deviceId}/currentTemperature')
  .onUpdate(async (change, context) => {
    const temp = change.after.val();
    const deviceId = context.params.deviceId;

    // Set your thresholds
    if (temp < 15 || temp > 30) {
      // Get the FCM token for the user/device (store this in your database)
      const tokenSnapshot = await admin.database().ref(`/devices/${deviceId}/fcmToken`).once('value');
      const fcmToken = tokenSnapshot.val();

      if (fcmToken) {
        const payload = {
          notification: {
            title: 'Temperature Alert',
            body: `Temperature is out of range: ${temp}°C`,
          }
        };
        await admin.messaging().sendToDevice(fcmToken, payload);
      }
    }
    return null;
  });