TAPO ON DAD'S WINDOWS PC -- 3 steps
===================================

You need TWO files together in one folder on dad's PC:
  1. Setup-Tapo-Emulator.ps1   (the installer)
  2. the Tapo .apkm file        (com.tplink.iot_...apkm -- the app)

STEP 1 - Copy both files into the same folder on dad's PC
   e.g. put them both on the Desktop, or in C:\Tapo\.

STEP 2 - Run the installer (once)
   Right-click  Setup-Tapo-Emulator.ps1  ->  "Run with PowerShell".
   - Click "Yes" when Windows asks for Administrator.
   - If Windows SmartScreen blocks it: "More info" -> "Run anyway".
   - It downloads Google's Android tools (~1.5 GB) and sets everything up.
     Leave it until it says DONE (several minutes on first run).

STEP 3 - Use it
   A "Tapo" icon is now on the Desktop. Double-click it.
   - First time: the emulator boots and installs Tapo (a few minutes).
   - After that: it quick-boots in seconds and Tapo opens automatically.

That's it. Dad just double-clicks "Tapo".

-----------------------------------------------------------------
NOTES / IF SOMETHING GOES WRONG
- Everything installs under  C:\Users\<dad>\AppData\Local\TapoEmulator
  To remove it all: delete that folder + the Desktop "Tapo" shortcut.
- If Tapo runs very SLOWLY: the PC's CPU virtualization is probably off.
  Reboot into BIOS/UEFI and enable "Virtualization" / "VT-x" / "SVM",
  then run the setup script again.
- Tapo is an ARM app; the emulator runs it through Google's built-in
  ARM->x86 translation, so it works but isn't as snappy as a phone.
- It is the official Google emulator -- no ads, no Chinese spyware.
- This was written on a Mac and not yet test-run on Windows, so if a step
  errors, copy the red error text and send it over -- it'll be a quick fix.
