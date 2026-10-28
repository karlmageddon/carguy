# Carguy standing instructions

Keep the device token out of chat, logs, and commits.

- Treat this as a persistent requirement; the user does not need to repeat it.
- Never print the token, include it in tool arguments or URLs, or save it in source files, documentation, test fixtures, screenshots, or Git history.
- When pairing or verifying the API, handle the token privately in memory and store it only in its intended Secret Manager/Keychain locations. Report safe status/count summaries instead of credential-bearing output.
