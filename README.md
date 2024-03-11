# XcodePluginLoader

Add plugin support back to Xcode 14+!

`XcodePluginLoader` is a lightweight, drop-in replacement for Xcode's built-in plugin system, which was removed in [Xcode 14.0b3](https://github.com/XVimProject/XVim2/issues/398).

It allows for loading the same plugin bundles that worked in older versions of Xcode.

## How it Works

`XcodePluginLoader` needs to be injected into Xcode (more on that below).
Once it's loaded, it aims to emulate the behavior of Xcode's original plugin loading system — searching for plugin bundles,
performing compatibility checks, and loading / initializing plugins.

A much deeper dive is available on [bryce.co](https://bryce.co/xcode-plugin-loader/).

## Installation

1) [Re-Sign Xcode](https://github.com/XVimProject/XVim2/blob/master/SIGNING_Xcode.md) (the same process you already had to in order to use plugins from Xcode 8 - Xcode 13)

(Note: this limits some functionality within Xcode. Consider keeping a signed copy of Xcode around as well. You can alternatively disable SIP at the expense of security)

2. Build or download the latest release of `XcodePluginLoader`
3. Copy `XcodePluginLoader.dylib` into `Xcode.app/Contents`
4. To run once, use `DYLD_INSERT_LIBRARIES=@executable_path/../XcodePluginLoader.dylib /path/to/Xcode.app/Contents/MacOS/Xcode`
5. For a more permanant setup, use [`optool`](https://github.com/alexzielenski/optool) to modify your Xcode binary to inject the plugin loader every time: `optool install -p "@executable_path/../XcodePluginLoader.dylib" -t /path/to/Xcode.app/Contents/MacOS/Xcode`

## Plugin Compatibility

Just like Xcode's original plugin system, this loader checks plugin bundles for compatibility before loading them. Plugins will have to be tested on newer Xcode versions and then updated to indicate that they're compatible.

For Xcode 14.0 - 15.2, plugins can add [`DVTPlugInCompatibilityUUIDs`](https://gist.github.com/minsko/9124ee24b9422fb8ea6b8d00815783ba) to their `Info.plist` files to specify which versions of Xcode they're compatible with.

For Xcode 15.3+, plugins should instead specify `CompatibleProductBuildVersions` in their `Info.plist` file, based on Xcode's build version (like `15E204a`).

These two compatibility values can exist side-by-side:

```xml
<key>CompatibleProductBuildVersions</key>
<array>
  <string>15E204a</string>  <!-- 15.3 -->
  <string>15E5178i</string> <!-- 15.3b1 -->
</array>
<key>DVTPlugInCompatibilityUUIDs</key>
<array>
  <string>EFD92DF8-D0A2-4C92-B6E3-9B3CD7E8DC19</string> <!-- 13.4 -->
  <string>7A3A18B7-4C08-46F0-A96A-AB686D315DF0</string> <!-- 13.2 -->
  <string>8BAA96B4-5225-471B-B124-D32A349B8106</string> <!-- 13.0 -->
</array>
```

## Debugging

When properly loaded into Xcode, `XcodePluginLoader` will log information about what it's doing; either use `Console.app` or launch Xcode via Terminal to see its output.
