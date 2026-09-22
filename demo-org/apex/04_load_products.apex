/* =============================================================================
 * DUG demo org — 04: products and opportunity line items
 * Run AFTER 01_load_core.apex.
 *
 * THE THING TO KNOW ABOUT THIS SCRIPT: once an opportunity has line items,
 * Salesforce stops honouring the Amount you wrote and recomputes it as the sum
 * of those line items. That would quietly destroy the careful amount spread
 * from script 01 — including Acme's exactly-$250K renewal, which the whole
 * slide 22 demo depends on.
 *
 * So every opportunity here gets exactly two line items whose totals sum to its
 * existing Amount to the dollar: a 70/30 split computed with integer-safe
 * rounding. Amount comes out unchanged. 05_verify_demo.apex checks this and
 * fails loudly if any amount drifted.
 *
 * Products are tagged with a DUG- ProductCode prefix so cleanup can find them.
 * ============================================================================= */

Organization thisOrg = [SELECT Id, Name, IsSandbox, OrganizationType FROM Organization LIMIT 1];
System.assert(
    thisOrg.IsSandbox || thisOrg.OrganizationType == 'Developer Edition',
    'REFUSING TO RUN. Not a Developer Edition org or sandbox: "' + thisOrg.Name + '".'
);

final String MARKER_LIKE = 'DUG-DEMO-%';
final String PRODUCT_LIKE = 'DUG-%';

// ---------------------------------------------------------------------------
// 1. The standard price book has to exist and be active before anything can be
//    priced. A fresh Developer Edition org ships it inactive.
// ---------------------------------------------------------------------------
List<Pricebook2> stdBooks = [SELECT Id, Name, IsActive FROM Pricebook2 WHERE IsStandard = true LIMIT 1];
System.assert(
    !stdBooks.isEmpty(),
    'No standard price book in this org, so opportunity products cannot be created. ' +
    'Skip script 04 — everything else works without it.'
);
Pricebook2 stdBook = stdBooks[0];
if (!stdBook.IsActive) {
    stdBook.IsActive = true;
    update stdBook;
    System.debug('Activated the standard price book.');
}

// ---------------------------------------------------------------------------
// 2. Clear line items from any previous 04 run. Products themselves are reused
//    rather than recreated — a Product2 with line items against it cannot be
//    deleted, so recreating them every run would fail on the second pass.
// ---------------------------------------------------------------------------
List<OpportunityLineItem> priorItems = [
    SELECT Id FROM OpportunityLineItem
    WHERE Opportunity.Account.AccountNumber LIKE :MARKER_LIKE
];
if (!priorItems.isEmpty()) {
    delete priorItems;
    System.debug('Removed ' + priorItems.size() + ' line item(s) from a previous run.');
}

// ---------------------------------------------------------------------------
// 3. Products and their standard prices
//    Format: ProductCode | Name | Family | ListPrice
// ---------------------------------------------------------------------------
List<String> productSpecs = new List<String>{
    'DUG-PLAT-CORE|Platform Core Licence|Licences|1200',
    'DUG-PLAT-ADV|Platform Advanced Licence|Licences|2400',
    'DUG-FS-MOB|Field Service Mobile|Licences|900',
    'DUG-ANALYTICS|Analytics Add-On|Add-Ons|1500',
    'DUG-INT-PACK|Integration Pack|Add-Ons|6000',
    'DUG-SENSOR|Line Sensor Package|Hardware|450',
    'DUG-SUP-PREM|Premium Support|Services|8000',
    'DUG-TRAIN|Administrator Training|Services|2200',
    'DUG-MIGRATE|Data Migration Services|Services|15000',
    'DUG-SANDBOX|Additional Sandbox|Add-Ons|3000'
};

Map<String, Product2> productsByCode = new Map<String, Product2>();
for (Product2 p : [SELECT Id, ProductCode FROM Product2 WHERE ProductCode LIKE :PRODUCT_LIKE]) {
    productsByCode.put(p.ProductCode, p);
}

List<Product2> newProducts = new List<Product2>();
for (String spec : productSpecs) {
    List<String> f = spec.split('\\|');
    if (!productsByCode.containsKey(f[0])) {
        newProducts.add(new Product2(
            ProductCode = f[0], Name = f[1], Family = f[2], IsActive = true,
            Description = 'Fictional product for the DUG demo org.'
        ));
    }
}
if (!newProducts.isEmpty()) {
    insert newProducts;
    for (Product2 p : newProducts) productsByCode.put(p.ProductCode, p);
    System.debug('Created ' + newProducts.size() + ' product(s).');
}

// Standard price book entries, again only where missing
Map<String, PricebookEntry> entriesByCode = new Map<String, PricebookEntry>();
for (PricebookEntry pbe : [
    SELECT Id, Product2.ProductCode FROM PricebookEntry
    WHERE Pricebook2Id = :stdBook.Id AND Product2.ProductCode LIKE :PRODUCT_LIKE
]) {
    entriesByCode.put(pbe.Product2.ProductCode, pbe);
}

List<PricebookEntry> newEntries = new List<PricebookEntry>();
for (String spec : productSpecs) {
    List<String> f = spec.split('\\|');
    if (!entriesByCode.containsKey(f[0])) {
        newEntries.add(new PricebookEntry(
            Pricebook2Id = stdBook.Id,
            Product2Id = productsByCode.get(f[0]).Id,
            UnitPrice = Decimal.valueOf(f[3]),
            IsActive = true
        ));
    }
}
if (!newEntries.isEmpty()) {
    insert newEntries;
    for (PricebookEntry pbe : newEntries) {
        for (String spec : productSpecs) {
            List<String> f = spec.split('\\|');
            if (productsByCode.get(f[0]).Id == pbe.Product2Id) {
                entriesByCode.put(f[0], pbe);
            }
        }
    }
    System.debug('Created ' + newEntries.size() + ' price book entry(ies).');
}

List<String> codes = new List<String>();
for (String spec : productSpecs) {
    String code = spec.split('\\|')[0];
    if (entriesByCode.containsKey(code)) codes.add(code);
}
System.assert(codes.size() >= 2, 'Need at least two priced products to split a deal across.');

// ---------------------------------------------------------------------------
// 4. Point every demo opportunity at the standard price book
// ---------------------------------------------------------------------------
List<Opportunity> demoOpps = [
    SELECT Id, Name, Amount, Pricebook2Id
    FROM Opportunity
    WHERE Account.AccountNumber LIKE :MARKER_LIKE AND Amount > 0
    ORDER BY Id
];
System.assert(!demoOpps.isEmpty(), 'No demo opportunities found. Run 01_load_core.apex first.');

List<Opportunity> needBook = new List<Opportunity>();
for (Opportunity o : demoOpps) {
    if (o.Pricebook2Id != stdBook.Id) {
        needBook.add(new Opportunity(Id = o.Id, Pricebook2Id = stdBook.Id));
    }
}
if (!needBook.isEmpty()) update needBook;

// ---------------------------------------------------------------------------
// 5. Two line items per opportunity, summing to its Amount exactly.
//
//    minor = floor(Amount * 0.3), major = Amount - minor. Both quantity 1, so
//    TotalPrice equals UnitPrice and the rollup lands on Amount to the dollar
//    with no rounding drift in either direction.
// ---------------------------------------------------------------------------
List<OpportunityLineItem> items = new List<OpportunityLineItem>();
Integer seed = 3301;
for (Integer i = 0; i < demoOpps.size(); i++) {
    Opportunity o = demoOpps[i];
    seed = Math.mod(seed * 75 + 74, 65537);

    Decimal minor = (o.Amount * 0.3).setScale(0, System.RoundingMode.DOWN);
    Decimal major = o.Amount - minor;
    if (minor <= 0) {          // tiny deals: keep it to a single line item
        minor = 0;
        major = o.Amount;
    }

    Integer aIdx = Math.mod(seed, codes.size());
    Integer bIdx = Math.mod(aIdx + 1 + Math.mod(seed / 7, codes.size() - 1), codes.size());

    items.add(new OpportunityLineItem(
        OpportunityId = o.Id,
        PricebookEntryId = entriesByCode.get(codes[aIdx]).Id,
        Quantity = 1, UnitPrice = major
    ));
    if (minor > 0) {
        items.add(new OpportunityLineItem(
            OpportunityId = o.Id,
            PricebookEntryId = entriesByCode.get(codes[bIdx]).Id,
            Quantity = 1, UnitPrice = minor
        ));
    }
}
insert items;

// ---------------------------------------------------------------------------
// 6. Confirm no amount moved. This is the whole risk of the script, so check it
//    here rather than waiting for someone to notice on stage.
// ---------------------------------------------------------------------------
Map<Id, Decimal> expected = new Map<Id, Decimal>();
for (Opportunity o : demoOpps) expected.put(o.Id, o.Amount);

Integer drifted = 0;
for (Opportunity o : [SELECT Id, Name, Amount FROM Opportunity WHERE Id IN :expected.keySet()]) {
    if (o.Amount != expected.get(o.Id)) {
        drifted++;
        if (drifted <= 5) {
            System.debug(LoggingLevel.ERROR, '  AMOUNT DRIFT: ' + o.Name + ' was $' +
                         expected.get(o.Id) + ', now $' + o.Amount);
        }
    }
}

System.debug('=====================================================');
System.debug('04 product load complete.');
System.debug('  Products in use:    ' + codes.size());
System.debug('  Opportunities priced: ' + demoOpps.size());
System.debug('  Line items:         ' + items.size());
if (drifted == 0) {
    System.debug('  Amount check: PASS — every opportunity amount survived intact.');
} else {
    System.debug(LoggingLevel.ERROR, '  Amount check: FAIL — ' + drifted +
                 ' opportunity amount(s) changed. The demo queries will be wrong. ' +
                 'Delete the line items (re-run this script) or skip script 04.');
}
System.debug('NEXT: run 05_verify_demo.apex');
System.debug('=====================================================');
