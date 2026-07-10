# Auth and Deep Links

Implemented auth flows:

- Register.
- Confirm email.
- Resend confirmation.
- Login.
- Logout.
- Session restoration.
- Forgot password.
- Password recovery deep link.
- Reset password.
- Change password.
- Change email request.

Development callback:

```text
worktracker://auth-callback
```

Android and iOS project files include custom scheme support. Production should replace this with verified HTTPS App Links / Universal Links when a domain is available.
