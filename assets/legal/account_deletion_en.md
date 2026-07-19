# How Finance Suit Account Deletion Works

Effective date: 19 July 2026

## Delete from the app

- Open Finance Suit and sign in.
- Open Settings.
- Select Delete account.
- Review the deletion notice, enter your current password, acknowledge the warning, and confirm.
- The app securely asks the Finance Suit server to delete the verified Finance Suit profile and its product data. Never send your password to support.

Successful in-app deletion is immediate for the active Finance Suit profile and product database. The app then removes its local authenticated session and locally stored preferences from that device.

## Request deletion without the app

Send an email to tarekian99@gmail.com from the address registered to your Finance Suit sign-in. Use the subject "Finance Suit account deletion" and state that you want the Finance Suit profile and associated Finance Suit data deleted. Do not send your password or financial records.

We may send a verification message to the registered address. Once verified, we will complete the request as soon as reasonably possible and no later than 30 days, unless law permits or requires a different period.

## Data deleted

- Profile and application preferences.
- Salary settings, adjustments, periods, and calculation snapshots.
- Work entries and official holidays.
- Finance accounts, balances derived from those accounts, categories, transactions, transfers, macros, and held amounts.
- Other active product records linked to the Supabase user ID.
- Local Finance Suit preferences on the device used for in-app deletion.

## Data retained

Finance Suit uses a shared Supabase authentication identity that may also provide access to another Building Suit or legacy finance portal. Finance Suit deletion therefore retains the shared authentication user, email/password credential, authentication metadata and sessions, and records belonging to those other products. Retaining them prevents deletion from Finance Suit from unexpectedly deleting another product account. Contact tarekian99@gmail.com separately if you need help concerning the shared identity or another portal.

## Limited delayed retention

Supabase operational logs are retained according to the hosting plan; the current plan exposes logs for up to one day. Protected backup copies, if maintained, may retain deleted rows for up to seven days before automatic expiry. Backups are isolated and are not used to restore an individual deleted account.

We may retain the minimum information necessary for security, fraud prevention, legal compliance, or resolving a deletion dispute. Anonymous information that can no longer reasonably identify you may also be retained.

## Important

Deletion cannot be undone. If you later sign in to Finance Suit using the retained shared identity, you can complete onboarding to create a new Finance Suit profile, but you must re-enter all information and deleted records are not restored. Deleting the app from your device does not delete Finance Suit server data; use the in-app deletion flow or contact tarekian99@gmail.com.

Developer: Tareq Abdelwhap
