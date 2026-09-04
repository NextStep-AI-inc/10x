# Settings Ownership and Composer Preferences Plan

## Goal

Split Settings into one OMP-owned category group and one small 10x-owned category group on the same navigation row. Keep one content surface, one owner-grouped search, every existing OMP control, provider entry, preferred IDE focus link, and OMP reset behavior. Store the approved composer interaction defaults in `UserDefaults` without writing OMP configuration.

## Implementation

1. Add `ComposerInteractionPreferences` with persisted default send behavior and a one-to-one mapping between Return shortcuts and actions. Reassigning an action swaps the displaced mapping so no action becomes duplicated.
2. Reshape `SettingsView` navigation into labeled OMP and 10x groups. OMP categories consume the remaining horizontal space and scroll when narrow; General and Composer stay right aligned.
3. Display only the selected category when there is no query. When searching, show matching OMP and 10x sections grouped by owner. Keep native settings usable while OMP is loading or unavailable.
4. Move the OMP path and setting count from the global header into OMP content. Keep Providers globally reachable and preserve preferred IDE focus routing.
5. Add focused tests for defaults, persistence, swap behavior, native matching/navigation, focus routing, and OMP-load-failure independence. Parent will regenerate the project and run coordinated Debug and Release verification.

## Boundaries

- No OMP wire or config writes for 10x preferences.
- No model favorites list in Settings; favorites remain in the model picker.
- No changes to `AppModel`, composer input handling, session control, providers, or generated project files in this slice.
