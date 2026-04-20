This is the initial commit for zbitxv2, this software ships with the zbitx v2 and it is an experimental upgrade to the original zbitx
Important: The original zbitx users should try this only if they know what they are doing. it is an early release yet

This (v2) version of the software differs significantly from the v1 software in the way it handles the front-panel. 

The V1 communicated with the front-panel with I2C digital lines. This caused the software to pause several times a second to service these lines causing a chugging sound as well as delays that interfered with the CW keying.

This is changed now. In v2 version, the raspberry pi's wifi simultaneously works as an access point (with the SSID 'zbitx') as well as the regular WiFi client that can connect to your WiFi access points. The zbitx front-panel connectsvia WiFi to the raspberry pi. All this comes preconfigured on the new zbitx v2.

For existing zbitx v1 users
This change requires upgrade of the zbitx front panel firmware (available as the zbitx_front_panel_v2.uf2 file in this repo) as well. 

The original zbitx users can try out this software by installing it side by side. This is done it two steps:

# Step 1: upgrade the software on the zbitx's raspberry pi
- flash the zbitx_front_panel_v2.uf2 into the front panel (the instructions are in the zbitx page 22)
- Connect a keyboard and mouse to your zbitx and boot up the zbitx.
- Open a new terminal (click on the terminal icon on the top).
- enter command : `cd ~` (this takes you to the home directory if you aren't already there)
- enter command : `mkdir sbitxv2` (creates a directory for the upgrade)
- enter command : `cd sbitxv2` (enter the directory)
- enter command : `git clone https://github.com/afarhan/zbitxv2.git` (this brings in the new version)
- enter command : `cp ~/sbitx/data/hw_settings.ini ~/sbitx/data/hw_settings.zbitxv1` (take a backup, just in case)
- enter command : `cd ~/sbitxv2/zbitxv2` (go into the zbitxv2 repository)
- enter command : `make` (this should build the zbitxv2 software)
- enter command : `sudo ./setup-ap.sh` (this will install the wifi access point 'zbitx' on the raspberry pi)
- open the ~/sbitx/data/hw_settings.ini file and add the following lines at the top:
  ```
	bfo_freq=40048000
	hw=4
	center_bin=600
  ```
	(save the file)

Now you are done. You can run the v2 version from ~/sbitxv2/zbitx:
```
cd ~/sbitxv2/zbitxv2
./sbitx
```
Confirm that the new version is running properly before proceeding to upgrade the zbitx firmware

# Step 2: upgrade the firmware on the zbitx front-panel
- Download the firmware file from https://github.com/afarhan/zbitxv2/blob/main/zbitx_front_panel_v2.ino.uf2
- Connect a USB cable from the port marked as CAT on the zbitx to your computer.
- Turn off the zbitx and turn it back on *while holding the tuning knob pusehd down* this puts the front panel into upload mode
- The zbitx front panel will now appear as an attached drive on your computer
- Copy the zbitx_front_panel_v2.ino.uf2 you just downloaded to the attached drive. The front-panel should now boot up after a few seconds

With both upgrades done, the front-panel will connect to the raspberry pi in a few seconds and  you can use the upgraded zbitxv2 firmware
now. Remember the new version can only be run from ~/sbitxv2/zbtixv2 directory. If you want to start using the new version permanently, just do this:
`cp ~/sbitxv2/zbitxv2/* ~/sbitx`
