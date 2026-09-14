# Set up Voxen

Voxen is a native macOS voice intent layer. It combines an AssemblyAI transcript with your current app, available website context, highlighted text, and writing preferences. The generated result is copied to your clipboard for review and manual pasting.

## Requirements

- macOS 14 or newer on Apple Silicon
- Xcode with the macOS 14 SDK
- An AssemblyAI API key
- An OpenRouter API key

## Build and launch

The easiest installation is the [latest GitHub Release](https://github.com/ivasuy/Voxen/releases/latest/download/Voxen-macOS-arm64.zip). Unzip it, move **Voxen.app** to Applications, then Control-click the app and choose **Open** for the first launch. GitHub builds are ad-hoc signed and not Apple-notarized.

To build from source, clone the repository and run the following commands from the project root:

```sh
bash scripts/build.sh
open build/Voxen.app
```

In Voxen, open **Settings** and:

1. Add both API keys.
2. Choose a writing model.
3. Choose a shortcut and click **Save**.
4. Enable **Microphone**.
5. Enable **Accessibility** for website and selected-text context.

Place the cursor in another app, press the shortcut to start recording, and press it again to finish. When Voxen shows **Copied**, paste with **Command + V**.

## Privacy

Voxen records and reads available context only after you trigger the shortcut. It does not continuously listen or inspect the screen. Audio is sent to AssemblyAI. The transcript, captured context, and enabled writing preferences are sent through OpenRouter to the model you selected. Generated text remains on the clipboard until you replace it.

Website and selected-text capture depends on what the foreground app exposes through macOS Accessibility. If context is unavailable, choose a manual mode or include the missing context in your spoken request.
