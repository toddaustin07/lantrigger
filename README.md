# lantrigger: A SmartThings Edge Driver

## Description
This SmartThings Edge driver is designed to work with *edgebridge* (https://github.com/toddaustin07/edgebridge) and provides a mechanism for LAN-based devices and applications to send a generic 'trigger' to SmartThings which can then be used in Automation routines and Rules as an IF condition.  

This can provides an analogous, yet 100% local, solution for cases where webCoRE pistons are triggered from LAN-based sources via a webCoRE piston URL.

This Edge driver can create any number of 'trigger' devices which each contain a button capability which is 'pushed' when a trigger message is received matching that device's configured name.  Each SmartThings device also includes a button on the device details screen to create additional LAN trigger devices.

## Pre-requisites

This driver requires that a forwarding bridge server is running on the LAN.  This bridge server can be obtained from this repository:  https://github.com/toddaustin07/edgebridge

## Driver Installation

The driver is installed via channel invitation.  Link is:  https://api.smartthings.com/invitation-web/accept?id=cc2197b9-2dce-4d88-b6a1-2d198a0dfdef

Once the driver has been installed to the hub, the user uses the mobile app to perform an 'Add device / Scan nearby' and a new device labeled "LAN-Triggered Device' is created and found in the 'No room assigned' room.

### Configuration

In the mobile app, go to the device's details screen and tap the 3 vertical-dot menu in the upper right corner and select **Settings**.  Provide the following:
- a unique name for the device - no special characters or blanks
- LAN address of the device or application - IP address *only* (e.g. '192.168.1.203')
- LAN address of the forwarding bridge server - *must* include port number (e.g. '192.168.1.150:8088')

## LAN Device or Application Configuration

The device or application on the LAN must be configured to send an HTTP **POST** to the bridge server with the following endpoint:
```
/<device name>/trigger
```

For example:
```
POST http://192.168.1.150:8088/mydevice/trigger
```

It is mandatory that the device name used in the endpoint string match that configured in the corresponding SmartThings device Settings, and must be followed by '/trigger'
