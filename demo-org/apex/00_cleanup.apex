/* =============================================================================
 * DUG demo org — 00: tear everything down
 * Run in: Developer Console -> Debug -> Open Execute Anonymous Window
 *
 * You do NOT need this before re-running the loaders — each one cleans up its
 * own scope first. This is for after the talk, or to reset the org completely.
 *
 * Order matters here:
 *   1. Campaign members and campaigns, before the contacts they point at
 *   2. Accounts — cascades to contacts, opportunities, cases, case comments,
 *      activities and opportunity line items
 *   3. Leads, which hang off nothing and so survive every cascade
 *   4. Products last, because a Product2 with line items against it cannot be
 *      deleted, and step 2 is what removes those line items
 *
 * Scope is limited to records carrying a demo marker. Nothing else is touched:
 *   Accounts   AccountNumber starts DUG-DEMO-
 *   Leads      email address ends @dug-demo.example
 *   Campaigns  child of the campaign named "DUG Demo Data"
 *   Products   ProductCode starts DUG-
 * ============================================================================= */

final String MARKER_LIKE = 'DUG-DEMO-%';
final String LEAD_LIKE = '%@dug-demo.example';
final String PARENT_CAMPAIGN = 'DUG Demo Data';
Integer removed = 0;

// ---------------------------------------------------------------------------
// 1. Campaigns. Children before the parent — a campaign with children cannot
//    be deleted. Deleting a campaign takes its members with it.
// ---------------------------------------------------------------------------
List<Campaign> children = [SELECT Id FROM Campaign WHERE Parent.Name = :PARENT_CAMPAIGN];
if (!children.isEmpty()) {
    delete children;
    removed += children.size();
    System.debug('Deleted ' + children.size() + ' campaign(s) and their members.');
}
List<Campaign> parents = [SELECT Id FROM Campaign WHERE Name = :PARENT_CAMPAIGN];
if (!parents.isEmpty()) {
    delete parents;
    Database.emptyRecycleBin(parents);
    removed += parents.size();
}

// ---------------------------------------------------------------------------
// 2. Accounts, and everything that hangs off them
// ---------------------------------------------------------------------------
List<Account> demoAccounts = [SELECT Id FROM Account WHERE AccountNumber LIKE :MARKER_LIKE];
if (demoAccounts.isEmpty()) {
    System.debug('No demo accounts found — nothing to cascade.');
} else {
    delete demoAccounts;
    Database.emptyRecycleBin(demoAccounts);
    removed += demoAccounts.size();
    System.debug('Deleted ' + demoAccounts.size() + ' account(s) and all their child records.');
}

// ---------------------------------------------------------------------------
// 3. Leads
// ---------------------------------------------------------------------------
List<Lead> demoLeads = [SELECT Id FROM Lead WHERE Email LIKE :LEAD_LIKE];
if (!demoLeads.isEmpty()) {
    delete demoLeads;
    Database.emptyRecycleBin(demoLeads);
    removed += demoLeads.size();
    System.debug('Deleted ' + demoLeads.size() + ' lead(s).');
}

// ---------------------------------------------------------------------------
// 4. Products and their price book entries. Deleting a Product2 removes its
//    entries with it. If a line item somewhere still references one, the delete
//    is refused — that means step 2 did not remove every line item, so look for
//    demo products attached to an opportunity outside the demo accounts.
// ---------------------------------------------------------------------------
List<Product2> demoProducts = [SELECT Id, Name FROM Product2 WHERE ProductCode LIKE 'DUG-%'];
if (!demoProducts.isEmpty()) {
    try {
        delete demoProducts;
        Database.emptyRecycleBin(demoProducts);
        removed += demoProducts.size();
        System.debug('Deleted ' + demoProducts.size() + ' product(s) and their price book entries.');
    } catch (DmlException e) {
        System.debug(LoggingLevel.WARN,
            'Could not delete the demo products: ' + e.getMessage() +
            ' — something outside the demo accounts still references them. The products are ' +
            'harmless if left in place; delete them by hand from Setup if you want them gone.');
    }
}

System.debug('=====================================================');
System.debug('Cleanup complete. ' + removed + ' top-level record(s) deleted, ' +
             'plus everything that cascaded from them.');
System.debug('');
System.debug('Left alone on purpose: anything Claude created during the demo that is not tied ' +
             'to a demo account, such as a task with no related record. Check your own open ' +
             'tasks if you want a completely clean slate.');
System.debug('=====================================================');
