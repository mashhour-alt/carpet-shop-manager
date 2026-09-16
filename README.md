# carpet-shop-manager

Flutter Android application for Saudi carpet-shop operations.

The project starts without sample data and persists operational data in SQLite on the device.

## Implemented first operating cycle

1. Create institution and payment-fee settings.
2. Create owner, accountant, seller and driver users.
3. Create suppliers.
4. Add inventory by item, colour, supplier, available length, supplier cost and seller wholesale price.
5. Record a sale with 4m default width, calculated area, payment method, driver trip, glue and iron consumption.
6. Deduct the sold running length in the same SQLite transaction.
7. Calculate seller commission from the wholesale/sale-price difference.
8. Show driver account per institution.
9. Show monthly seller settlement and record withdrawals, expenses, deductions and payments.

## Build

GitHub Actions builds an installable release APK when a GitHub Release is published or from **Actions → Build Android Release APK → Run workflow**. The output is attached as the `carpet-shop-manager-release-apk` artifact.
