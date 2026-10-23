## Summary

<!-- What does this change and why? Link the issue it resolves, for example "Closes #12". -->

## Changes

-

## Screenshots or recording

<!-- Required for visual changes: before and after, light and dark appearance. Remove personal data. -->

## Testing

<!-- How did you verify the change? List new or updated tests and any manual checks. -->

- [ ] `make lint` passes
- [ ] `make test` passes (package tests and UI tests)
- [ ] Tested manually in the running app

## Checklist

- [ ] The change is original work and contains no code or assets from Arc or other proprietary products
- [ ] Every new control, menu item and shortcut works end to end (no placeholders)
- [ ] Business rules are in `MarcCore` and covered by unit tests
- [ ] VoiceOver labels, keyboard access and Reduce Motion are handled for new UI
- [ ] `CHANGELOG.md` has an entry under *Unreleased* for user-visible changes
- [ ] Security-sensitive areas (autofill, Keychain, navigation policy, extensions, updates) are called out above
