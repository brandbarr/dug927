/* =============================================================================
 * Intro to Claude and Salesforce — tear down the demo data
 * Run in: Developer Console -> Debug -> Open Execute Anonymous Window
 *
 * You do NOT need this before re-running the loader — 01_load_demo_data.apex
 * cleans up after itself. This is for after the talk, or if you want the org
 * empty for some other reason.
 *
 * Deletes every account tagged 'DUG-DEMO-*' and empties them from the recycle
 * bin. Account deletion cascades to the demo contacts, opportunities, cases and
 * activities, so nothing is left behind.
 *
 * It cannot touch anything it did not create: the only records in scope are the
 * ones carrying the DUG-DEMO- marker on AccountNumber.
 * ============================================================================= */

final String MARKER = 'DUG-DEMO-';
final String MARKER_LIKE = MARKER + '%';   // SOQL binds need a plain variable

List<Account> demoAccounts = [
    SELECT Id, Name FROM Account WHERE AccountNumber LIKE :MARKER_LIKE
];

if (demoAccounts.isEmpty()) {
    System.debug('Nothing to clean up — no accounts tagged ' + MARKER + '* in this org.');
} else {
    System.debug('Deleting ' + demoAccounts.size() + ' demo account(s) and everything under them:');
    for (Account a : demoAccounts) {
        System.debug('  - ' + a.Name);
    }
    delete demoAccounts;
    Database.emptyRecycleBin(demoAccounts);
    System.debug('Done. Demo data removed.');
}

// Tasks Claude created during the demo hang off the demo records, so the
// cascade above takes them with it. Anything Claude created that is NOT tied to
// a demo account — a stray task with no WhatId, for example — is left alone on
// purpose. Check your own open tasks if you want a completely clean slate.
