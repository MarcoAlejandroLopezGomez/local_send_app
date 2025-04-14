# LocalSendApp

LocalSendApp is a Flutter application designed for simple peer-to-peer file sharing between devices on the same local network (Wi-Fi). It uses mDNS (Bonjour/Zeroconf) for device discovery and direct TCP socket connections for file transfers, eliminating the need for internet access or central servers.
.
## Features

*   **Local Network Discovery:** Automatically discovers other devices running LocalSendApp on the same Wi-Fi network using mDNS.
*   **Direct File Transfer:** Sends files directly between devices using TCP sockets.
*   **Cross-Platform (Potential):** Built with Flutter, aiming for compatibility across multiple platforms (Windows tested, mobile requires platform-specific setup).
*   **Customizable Device Name:** Allows users to set a recognizable name for their device.
*   **Simple UI:** Basic interface showing nearby devices and transfer progress.

## How it Works

1.  **Discovery:** When the app starts, it begins listening for mDNS announcements for the `_localsend._tcp` service type on the local network. It also (implicitly, depending on the OS) advertises its own presence.
2.  **Peer List:** Discovered devices (peers) are displayed in a list on the main screen.
3.  **Transfer Initiation:** Users can select a file to send to a specific discovered peer.
4.  **TCP Connection:** The sending device initiates a TCP connection to the receiving device's IP address and port (obtained via mDNS).
5.  **File Transmission:** File metadata (like name and size) is sent first, followed by the file content streamed over the TCP socket.
6.  **Receiving:** The receiving device listens on a specific port, accepts incoming connections, receives the metadata, and saves the incoming file stream, typically to the Downloads folder.

## Setup and Running

1.  **Install Flutter:** Ensure you have the Flutter SDK installed and configured on your system. See the [official Flutter installation guide](https://docs.flutter.dev/get-started/install).
2.  **Clone the Repository:**
    ```bash
    git clone <https://github.com/MarcoAlejandroLopezGomez/local_send_app.git>
    cd local_send_app
    ```
3.  **Get Dependencies:**
    ```bash
    flutter pub get
    ```
4.  **Run the App:**
    *   Connect your target device (or run an emulator/simulator).
    *   Ensure the device is connected to a Wi-Fi network.
    *   Run the app:
        ```bash
        flutter run
        ```
    *   For desktop (e.g., Windows): Ensure you have the necessary build tools installed (like Visual Studio for Windows development). Select your target device in VS Code or use the command line:
        ```bash
        flutter run -d windows # or linux, macos
        ```

## Usage

1.  Launch LocalSendApp on two or more devices connected to the **same Wi-Fi network**.
2.  On the `Home` screen, wait for nearby devices to appear in the 'Nearby Devices' list.
3.  To send a file:
    *   Tap the 'Send File' button next to the desired recipient device.
    *   Select the file you wish to send using the native file picker.
4.  The file transfer will begin, and progress will be shown in the 'Transfers' section.
5.  Received files are typically saved to the device's Downloads folder.
6.  You can change your device's advertised name in the `Settings` screen.

## Acknowledgements

A significant portion of the core logic, provider implementation, mDNS handling, and troubleshooting guidance for this project was developed with the assistance of **Gemini 2.5 Pro Preview (internal date stamp 03-25)**. Its insights into Flutter state management, network protocols, and platform-specific considerations were invaluable.

## Notes

*   **Network:** All devices MUST be on the same local Wi-Fi network. Creating a hotspot on one device (Windows Hosted Network or mobile hotspot) can work if other devices connect to it.
*   **Firewall:** Ensure your system's firewall allows the application to communicate over the local network (especially for mDNS on UDP port 5353 and the TCP port used for transfers).
*   **Mobile Permissions:** Building for Android/iOS requires configuring specific network and storage permissions in `AndroidManifest.xml` and `Info.plist`.
*   **mDNS Advertising:** The current implementation relies more on listening than explicit advertising due to complexities with the `multicast_dns` package API. Discoverability *of* this device *by* others might vary depending on the OS's native mDNS handling.
