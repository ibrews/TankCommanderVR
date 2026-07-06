Both GOOGLE_API_KEY and GEMINI_API_KEY are set. Using GOOGLE_API_KEY.
Both GOOGLE_API_KEY and GEMINI_API_KEY are set. Using GOOGLE_API_KEY.
Attempt 1 failed with status 503. Retrying with backoff... ApiError: {"error":{"code":503,"message":"This model is currently experiencing high demand. Spikes in demand are usually temporary. Please try again later.","status":"UNAVAILABLE"}}
    at throwErrorIfNotOK (file:///C:/Users/Sam/AppData/Roaming/npm/node_modules/@google/gemini-cli/node_modules/@google/genai/dist/node/index.mjs:11716:30)
    at process.processTicksAndRejections (node:internal/process/task_queues:104:5)
    at async file:///C:/Users/Sam/AppData/Roaming/npm/node_modules/@google/gemini-cli/node_modules/@google/genai/dist/node/index.mjs:11454:13
    at async Models.generateContent (file:///C:/Users/Sam/AppData/Roaming/npm/node_modules/@google/gemini-cli/node_modules/@google/genai/dist/node/index.mjs:12766:24)
    at async file:///C:/Users/Sam/AppData/Roaming/npm/node_modules/@google/gemini-cli/node_modules/@google/gemini-cli-core/dist/src/core/loggingContentGenerator.js:102:34
    at async retryWithBackoff (file:///C:/Users/Sam/AppData/Roaming/npm/node_modules/@google/gemini-cli/node_modules/@google/gemini-cli-core/dist/src/utils/retry.js:128:28)
    at async BaseLlmClient._generateWithRetry (file:///C:/Users/Sam/AppData/Roaming/npm/node_modules/@google/gemini-cli/node_modules/@google/gemini-cli-core/dist/src/core/baseLlmClient.js:141:20)
    at async BaseLlmClient.generateJson (file:///C:/Users/Sam/AppData/Roaming/npm/node_modules/@google/gemini-cli/node_modules/@google/gemini-cli-core/dist/src/core/baseLlmClient.js:44:24)
    at async ClassifierStrategy.route (file:///C:/Users/Sam/AppData/Roaming/npm/node_modules/@google/gemini-cli/node_modules/@google/gemini-cli-core/dist/src/routing/strategies/classifierStrategy.js:126:34)
    at async CompositeStrategy.route (file:///C:/Users/Sam/AppData/Roaming/npm/node_modules/@google/gemini-cli/node_modules/@google/gemini-cli-core/dist/src/routing/strategies/compositeStrategy.js:33:34) {
  status: 503
}
### 1) META QUEST OCULUS USERNAME API

**Can an in-app Godot/OpenXR build read the display name / username?**
Yes, but it requires direct integration with the Meta Platform SDK (formerly Oculus Platform SDK). It cannot be done natively through standard OpenXR or base Godot APIs.

**Meta Platform SDK & Requirements (Authoritative)**
To access user data, you must:
1. **Configure the Dashboard:** Register an App ID in the Meta Quest Developer Dashboard.
2. **Data Use Checkup:** Apply for the "User ID" and "User Profile" permissions. Meta must approve your use case (e.g., displaying names in multiplayer).
3. **Entitlement Check:** Your app must successfully pass a platform entitlement check before the API will return valid user data.
4. **User API:** The SDK provides functions like `ovr_User_GetLoggedInUser()` for the local player and `ovr_User_Get(userID)` for remote players (if you have their Meta ID from a matchmaking or relay service).

**Godot Integration & GDExtension State (Authoritative/Speculative)**
*Godot 4.x does not include the Meta Platform SDK out of the box.* While OpenXR handles rendering and tracking, platform features require a separate plugin. 
*   **Current Ecosystem:** You must rely on community-maintained GDExtensions (like `godot-meta-platform-sdk` forks) or write your own C++ GDExtension / Android JNI wrapper bridging the `ovrplatformsdk`.
*   **Realistic Effort:** **High.** Wiring up the SDK requires setting up a custom build pipeline, initializing the platform SDK on boot, handling Meta's asynchronous message queue within your Godot `_process` loop, and passing App Lab/Store app reviews.
*   **The Alternative (Self-Reporting):** **Low Effort.** Allowing players to type a name into a UI (or generating a random one) and passing it via a Godot multiplayer RPC upon connection takes minutes. Unless you need strict identity verification, friends lists, or persistent cloud saves, self-reporting is vastly superior for prototyping and early production.

---

### 2) GODOT SPLASH SCREEN BEST PRACTICES

**How production Godot 4.x games implement pre-lobby loading (Authoritative)**

Production games split the boot process into two distinct phases: the engine boot splash and a dedicated, interactive loading scene.

**1. Project Settings Boot Splash**
*   **What it is:** Configured in `Project Settings -> Application -> Boot Splash`. 
*   **Best Practice:** Keep this minimal (e.g., a simple static logo or black screen). This image displays while the engine's core initializes. It blocks the main thread, meaning you cannot animate it, and it cannot display real-time loading progress.

**2. Dedicated Splash/Loading Scene (`Splash.tscn`)**
*   **What it is:** Set this as your project's "Main Scene". Once the engine initializes, this scene loads instantly because it is lightweight (UI elements only, no heavy 3D assets).
*   **The Sequence:** 
    1. `Splash.tscn` plays studio logo animations using an `AnimationPlayer`.
    2. Once logos finish, it reveals a loading bar or spinner.
    3. It triggers background loading of the heavy `MainMenu.tscn` or lobby.

**3. Async Loading via `ResourceLoader`**
Godot 4 handles non-blocking loads via the `ResourceLoader` singleton.
*   **Start Loading:** Call `ResourceLoader.load_threaded_request("res://scenes/MainMenu.tscn")`. This pushes the heavy I/O and parsing to a background thread.
*   **Track Progress:** In your `Splash.tscn`'s `_process(delta)` function, pass an array to `ResourceLoader.load_threaded_get_status(path, progress_array)`.
*   **Update UI:** The `progress_array[0]` will contain a float from `0.0` to `1.0`. Update your `ProgressBar.value` with this number.
*   **Swap Scenes:** When the status returns `ResourceLoader.THREAD_LOAD_LOADED`, retrieve the fully parsed scene with `ResourceLoader.load_threaded_get(path)`. Finally, swap to it safely using `get_tree().change_scene_to_packed(loaded_scene)`.

**Example in Open Source XR**
Projects like the official **Godot XR Tools** demo adhere to this pattern. They boot into a lightweight "Staging" or "Loading" environment—often a simple dark void with a floating UI panel. Because XR requires rendering at 72-90fps continuously to prevent motion sickness, the loading scene keeps the XR compositor fed with a basic environment while `ResourceLoader.load_threaded_request` quietly prepares the complex main game scene in the background.

---

### 3) 
*(Skipped as requested)*
