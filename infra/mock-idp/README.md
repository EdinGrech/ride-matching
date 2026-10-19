# Local Mock Identity Provider

Start the test-only OIDC issuer from the repository root. You need Docker Compose v2.

```powershell
docker compose up -d mock-idp
```

The issuer is `http://localhost:8090/ride` and its JWK endpoint is `http://localhost:8090/ride/jwks`.

Use any unique `driver-*`, `rider-*`, or `admin-*` subject on the interactive login screen, for example `driver-alex` or `rider-sam`. The mock issuer copies that subject into the signed JWT's `sub` claim and adds the corresponding `DRIVER`, `RIDER`, or `ADMIN` role claim. Open `http://localhost:8090/ride/debugger` to run the authorization-code flow and inspect its access token.

The Spring Boot local profile already uses these URLs. Set `JWT_ISSUER_URI` and `JWT_JWK_SET_URI` only when overriding the default configuration.

Stop the issuer when finished:

```powershell
docker compose stop mock-idp
```

This issuer is for local testing only. Use a production identity provider outside development.
