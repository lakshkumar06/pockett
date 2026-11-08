# Experience API v2

Frozen following Agent 2 milestone 1 agreement. JSON over HTTPS; loopback HTTP permitted for local development only. Authentication is existing `POST /login {username,password}` -> `{token,username}`, then `Authorization: Bearer <token>`. No credential is part of configuration.

`POST /experiences` accepts exactly `{configuration, sourceURL?}`. Configuration follows experience.schema.json and semantic rules in capabilities.md. Maximum configuration size 65536 UTF-8 bytes, request 73728 bytes. sourceURL is optional HTTPS without userinfo, whitespace, query or fragment, max 2048 characters. It is provenance only; the server stores the submitted validated snapshot and never fetches the URL.

Upsert key is authenticated owner + configuration.creatorKey. First revision is 1; each accepted publish increments revision and retains appId. Response: `{appId, revision, deepLink}` with `deepLink = "pocket://app/" + appId`. IDs are opaque server-generated identifiers, never creatorKey.

`GET /experiences/:id` returns `{appId, revision, configuration, sourceURL?}` to owner or shared recipients. Omitted sourceURL may also be null on read. No anonymous reads. Errors use `{error}`: 400 validation, 401 missing/expired/invalid authentication, 403 owner-only mutation, 404 absent or unauthorized resource. Clients must not log backend error bodies or tokens.

Existing `/apps` and `/apps/:id/shares` remain the access authority. Native listing adds kind:"native", revision, creatorKey, url:null. Web listing has kind:"web" and its original URL. Sharing does not allow publishing under another owner's identity. Deletion removes the snapshot via app lifecycle. Creator code never receives Pocket credentials.
