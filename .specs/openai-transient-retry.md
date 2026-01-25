# OpenAI + ChatGPT Transient Retry Policy

## Overview

Add retry eligibility for transient HTTP status codes returned by the OpenAI provider, including ChatGPT OAuth/Codex traffic. The retry loop already exists in the session processor; this spec ensures OpenAI/ChatGPT errors are marked as retryable so the existing backoff and Retry-After handling kick in.

## Goals

- Mark OpenAI/ChatGPT errors with specific transient status codes as retryable.
- Reuse the existing SessionRetry delay and Retry-After header handling.
- Keep error messages and metadata intact for user visibility and diagnostics.

## Non-goals

- Changing retry backoff behavior or limits outside of the existing SessionRetry logic.
- Modifying retry logic for non-OpenAI providers.
- Introducing new UI elements beyond the existing retry status display.

## Background

- Session retries are driven by `SessionRetry.retryable()` in `packages/opencode/src/session/retry.ts`.
- `SessionProcessor` retries when `MessageV2.APIError.data.isRetryable` is true.
- `MessageV2.fromError` preserves `APICallError.isRetryable`, but OpenAI/ChatGPT transient status codes are not consistently marked retryable today.

## Requirements

### Scope

- Provider: OpenAI, including ChatGPT OAuth/Codex calls.
- Provider identification: `providerID === "openai"` for OpenAI API and the ChatGPT OAuth/Codex fetch path.

### Transient status codes

Treat the following HTTP status codes as transient and retryable for OpenAI/ChatGPT:

- 404
- 408
- 429
- 500
- 502
- 503
- 504

### Behavior

- When an OpenAI/ChatGPT request fails with a status code in the transient list, mark the resulting `MessageV2.APIError.data.isRetryable` as `true`.
- If `isRetryable` is already `true`, keep it `true` (do not override it to `false`).
- Preserve existing error message formatting, response headers, and response body.
- If the status code is not in the list, preserve existing retryability behavior.
- If no HTTP status code is available (network failures, status `0`), preserve existing retryability behavior.
- Continue to respect Retry-After headers through the existing `SessionRetry.delay` logic.
- Abort errors (`AbortError`) remain non-retryable and exit the loop as they do today.

## Implementation notes

- The retryable status determination can be applied where `APICallError` is converted into `MessageV2.APIError` (e.g., `MessageV2.fromError` in `packages/opencode/src/session/message-v2.ts`) or at the OpenAI provider error handler layer.
- Restrict the override to `providerID === "openai"` and, when available, OpenAI/ChatGPT endpoints to avoid impacting other providers.
- ChatGPT/Codex traffic uses `https://chatgpt.com/backend-api/codex/responses` (see `packages/opencode/src/plugin/codex.ts`); when request URLs are available, use this host/path to identify the ChatGPT/Codex path.

## Testing

- Unit tests for `MessageV2.fromError` (or the chosen mapping layer) that assert `isRetryable` becomes `true` for each transient status code when `providerID` is `openai`.
- Unit test coverage that a non-transient status code (for example 400) remains non-retryable for OpenAI.
- Tests that ChatGPT/Codex requests with transient status codes are marked retryable when the request URL points at `chatgpt.com/backend-api/codex/responses`.

## Acceptance criteria

- OpenAI and ChatGPT OAuth/Codex calls that return a transient status code trigger the retry loop and show the existing retry UI status.
- Retry delay continues to respect Retry-After headers for OpenAI/ChatGPT errors.
- No behavior changes for non-OpenAI providers.

## Risks and mitigations

- **404 treated as transient:** This can mask configuration errors. The behavior is explicitly required and limited to OpenAI/ChatGPT to reduce blast radius.
