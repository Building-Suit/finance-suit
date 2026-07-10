# Resend Setup

Production email requires external credentials.

1. Create a Resend account.
2. Add the sending domain.
3. Add required DNS records.
4. Wait for domain verification.
5. Create SMTP credentials in Resend.
6. Configure Supabase Auth custom SMTP.
7. Set sender name.
8. Set sender email.
9. Add redirect URLs for registration confirmation and password recovery.
10. Test registration confirmation, resend confirmation, password reset, and email change.
11. Inspect Supabase Auth logs and Resend delivery logs.
12. Keep development and production sending domains separate.

Do not put the Resend API key or SMTP password in Flutter config.
