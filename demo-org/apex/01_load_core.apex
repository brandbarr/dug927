/* =============================================================================
 * DUG demo org — 01: core records
 * Accounts, contacts, opportunities (current + historical) and activity history.
 *
 * Run in: Developer Console -> Debug -> Open Execute Anonymous Window
 *
 * RUN THIS FIRST. Scripts 02-04 look up the records it creates, so the order
 * 01 -> 02 -> 03 -> 04 matters. Re-running 01 wipes and rebuilds the accounts,
 * which cascade-deletes everything 02 and 04 created, so if you re-run 01 you
 * must re-run 02, 03 and 04 behind it.
 *
 * Creates 1,577 records: 250 accounts, 396 contacts, 360 opportunities (161 open,
 * 199 closed history) and 571 activities. Generated from a fixed seed, so every
 * run produces byte-identical data and you can trust what you rehearsed against.
 * ============================================================================= */

// ---------------------------------------------------------------------------
// 0. Safety rail — never let this touch a real org
// ---------------------------------------------------------------------------
Organization thisOrg = [SELECT Id, Name, IsSandbox, OrganizationType FROM Organization LIMIT 1];
System.assert(
    thisOrg.IsSandbox || thisOrg.OrganizationType == 'Developer Edition',
    'REFUSING TO RUN. This looks like a production org: "' + thisOrg.Name +
    '" (' + thisOrg.OrganizationType + '). Load demo data into a Developer Edition org ' +
    'or a sandbox only. If you really mean to run here, delete this assert block.'
);

final String MARKER = 'DUG-DEMO-';
final String MARKER_LIKE = MARKER + '%';
final Integer FILLER_ACCOUNTS = 249;   // + Acme = 250

// ---------------------------------------------------------------------------
// 1. Wipe any previous run. Deleting the accounts cascades to their contacts,
//    opportunities, cases, activities and opportunity products.
// ---------------------------------------------------------------------------
List<Account> priorRun = [SELECT Id FROM Account WHERE AccountNumber LIKE :MARKER_LIKE];
if (!priorRun.isEmpty()) {
    delete priorRun;
    Database.emptyRecycleBin(priorRun);
    System.debug('Cleaned up ' + priorRun.size() + ' account(s) from a previous run.');
}

// ---------------------------------------------------------------------------
// 2. Picklist safety — validate everything against this org's real values
// ---------------------------------------------------------------------------
Set<String> validStages = new Set<String>();
for (Schema.PicklistEntry pe : Opportunity.StageName.getDescribe().getPicklistValues()) {
    if (pe.isActive()) validStages.add(pe.getValue());
}
Set<String> validIndustries = new Set<String>();
for (Schema.PicklistEntry pe : Account.Industry.getDescribe().getPicklistValues()) {
    if (pe.isActive()) validIndustries.add(pe.getValue());
}
Set<String> validOppTypes = new Set<String>();
for (Schema.PicklistEntry pe : Opportunity.Type.getDescribe().getPicklistValues()) {
    if (pe.isActive()) validOppTypes.add(pe.getValue());
}
Set<String> validAccountTypes = new Set<String>();
for (Schema.PicklistEntry pe : Account.Type.getDescribe().getPicklistValues()) {
    if (pe.isActive()) validAccountTypes.add(pe.getValue());
}
Set<String> validTaskStatus = new Set<String>();
for (Schema.PicklistEntry pe : Task.Status.getDescribe().getPicklistValues()) {
    if (pe.isActive()) validTaskStatus.add(pe.getValue());
}

String customerType = validAccountTypes.contains('Customer - Direct') ? 'Customer - Direct' : null;
String prospectType = validAccountTypes.contains('Prospect') ? 'Prospect' : customerType;
String newCustType  = validOppTypes.contains('New Customer') ? 'New Customer' : null;
String upgradeType  = validOppTypes.contains('Existing Customer - Upgrade')
    ? 'Existing Customer - Upgrade' : null;
// LastActivityDate only rolls up from COMPLETED tasks, so this value matters.
String doneStatus = validTaskStatus.contains('Completed')
    ? 'Completed' : new List<String>(validTaskStatus)[0];

// Open stages, in rough pipeline order, filtered to what this org actually has.
List<String> openStages = new List<String>();
for (String candidate : new List<String>{
        'Prospecting', 'Qualification', 'Needs Analysis',
        'Value Proposition', 'Proposal/Price Quote', 'Negotiation/Review'}) {
    if (validStages.contains(candidate)) openStages.add(candidate);
}
if (openStages.isEmpty()) openStages.add(new List<String>(validStages)[0]);
String wonStage  = validStages.contains('Closed Won') ? 'Closed Won' : null;
String lostStage = validStages.contains('Closed Lost') ? 'Closed Lost' : null;

// ---------------------------------------------------------------------------
// 3. Owners. You keep Acme and a large share of the pipeline so "which of MY
//    opportunities..." returns something meaty; the rest spreads across other
//    users so the dashboard's "filter by owner" has real groups to filter.
// ---------------------------------------------------------------------------
List<Id> owners = new List<Id>{ UserInfo.getUserId() };
for (User u : [
    SELECT Id FROM User
    WHERE IsActive = true AND UserType = 'Standard' AND Id != :UserInfo.getUserId()
    ORDER BY CreatedDate ASC
    LIMIT 5
]) {
    owners.add(u.Id);
}
if (owners.size() == 1) {
    System.debug(LoggingLevel.WARN,
        '*** Only one active standard user in this org, so all 250 accounts will be yours. ' +
        'The "filter by owner" part of the dashboard demo will look flat. Create a few extra ' +
        'users first if you want that to land. ***');
}

// ---------------------------------------------------------------------------
// 4. Dates. Everything is relative to today so this stays correct whenever you
//    re-run it. "This quarter" here is the CALENDAR quarter; if your org uses a
//    custom fiscal year, SOQL's THIS_QUARTER follows the fiscal calendar and
//    05_verify_demo.apex will tell you the two disagree.
// ---------------------------------------------------------------------------
Date today = Date.today();
Integer qIndex = (today.month() - 1) / 3;
Date qStart = Date.newInstance(today.year(), qIndex * 3 + 1, 1);
Date qEnd = qStart.addMonths(3).addDays(-1);
Integer daysLeftInQuarter = Math.max(today.daysBetween(qEnd), 1);

// ---------------------------------------------------------------------------
// 5. Deterministic pseudo-random numbers.
//    A fixed-seed LCG, precomputed into a list so the generation loops can just
//    index into it. Same seed every run means the org rebuilds identically —
//    you can rehearse against it and trust what you saw.
//    Multiplier and modulus are chosen to stay inside Integer range.
// ---------------------------------------------------------------------------
List<Integer> rnd = new List<Integer>();
Integer seed = 20260924;
for (Integer i = 0; i < 6600; i++) {
    seed = Math.mod(seed * 75 + 74, 65537);
    rnd.add(seed);
}

// ---------------------------------------------------------------------------
// 6. Name and industry vocabulary. Prefix x suffix gives far more unique
//    combinations than we need, and pairing is deterministic so no duplicates.
// ---------------------------------------------------------------------------
List<String> prefixes = new List<String>{
    'Northgate', 'Harbor Point', 'Cedar Ridge', 'Vantage', 'Bluefield',
    'Sable Creek', 'Ironwood', 'Lakeside', 'Pioneer', 'Summit Ridge',
    'Copper Lane', 'Meridian', 'Fairmont', 'Redstone', 'Orchard Park',
    'Talon', 'Willow Bend', 'Kestrel', 'Granite Bay', 'Beacon Hill',
    'Silverlake', 'Dunmore', 'Halcyon', 'Thornton', 'Westbrook',
    'Kingsford', 'Ravenswood', 'Ashford', 'Brightwater', 'Calder',
    'Elmgrove', 'Fenwick', 'Glenmoor', 'Hartley', 'Inverness',
    'Jasper Falls', 'Kenwood', 'Larkspur', 'Montrose', 'Norwood',
    'Oakhaven', 'Pemberton', 'Quarry Hill', 'Rosemont', 'Stonebridge',
    'Tallgrass', 'Umberton', 'Verdant', 'Windrow', 'Yarrow',
    'Ambler', 'Braxton', 'Coventry', 'Drexel', 'Eastport',
    'Fallbrook', 'Gainsborough', 'Holloway', 'Ridgeline', 'Saltmarsh'
};
// Suffix paired with the industry it implies, so names and industries agree.
List<String> suffixes = new List<String>{
    'Manufacturing|Manufacturing', 'Fabrication|Manufacturing', 'Industries|Manufacturing',
    'Logistics|Transportation', 'Freight Systems|Transportation',
    'Health Partners|Healthcare', 'Medical Group|Healthcare',
    'Utilities|Utilities', 'Power Cooperative|Energy',
    'Insurance Group|Insurance', 'Financial|Banking', 'Capital Partners|Finance',
    'Foods|Food & Beverage', 'Construction|Construction', 'Ag Supply|Agriculture',
    'Education Trust|Education', 'Retail Group|Retail', 'Biotech|Biotechnology',
    'Hospitality|Hospitality', 'Media Group|Media', 'Security Systems|Technology',
    'Senior Living|Healthcare', 'Aerospace|Manufacturing', 'Technologies|Technology',
    'Chemical Works|Chemicals', 'Engineering Group|Engineering',
    'Communications|Communications', 'Electronics|Electronics',
    'Shipping Lines|Shipping', 'Environmental Services|Environmental'
};
List<String> firstNames = new List<String>{
    'Amara', 'Devon', 'Lucia', 'Bennett', 'Rina', 'Tomas', 'Gwen', 'Isaiah',
    'Marta', 'Owen', 'Simone', 'Felix', 'Nadia', 'Curtis', 'Elena', 'Jae',
    'Harriet', 'Ravi', 'Colette', 'Malik', 'Sofia', 'Declan', 'Yuki', 'Terrence',
    'Ingrid', 'Omar', 'Bianca', 'Hugo', 'Leila', 'Grant', 'Anika', 'Pierce',
    'Rosa', 'Emeka', 'Astrid', 'Julian', 'Naomi', 'Sven', 'Camila', 'Bashir'
};
List<String> lastNames = new List<String>{
    'Osei', 'Pryce', 'Ferrante', 'Shaw', 'Kapoor', 'Delgado', 'Halloway', 'Brandt',
    'Kowalski', 'Tanaka', 'Achebe', 'Arnaud', 'Rostami', 'Vale', 'Sorokin', 'Min',
    'Boyle', 'Chandrasekar', 'Okafor', 'Lindqvist', 'Moreau', 'Byrne', 'Nakamura',
    'Ellison', 'Solberg', 'Haddad', 'Ricci', 'Vermeer', 'Nasser', 'Whitlock',
    'Petrov', 'Gallagher', 'Santos', 'Adeyemi', 'Lindgren', 'Batista', 'Reyes-Cruz',
    'Eriksen', 'Fontaine', 'Rahimi'
};
List<String> titles = new List<String>{
    'Director of Operations', 'VP Sales', 'CIO', 'Head of Procurement',
    'Operations Manager', 'Director of IT', 'CFO', 'Plant Manager',
    'VP Customer Experience', 'Business Systems Manager', 'Chief of Staff',
    'Director of Finance', 'Head of Field Service', 'Quality Director',
    'Salesforce Administrator', 'Revenue Operations Lead'
};
List<String> dealLabels = new List<String>{
    'Platform Rollout', 'Annual Renewal', 'Field Service Expansion',
    'Data Migration', 'Analytics Bundle', 'Licence Expansion',
    'Integration Project', 'Pilot Program', 'Regional Deployment',
    'Support Upgrade', 'Automation Phase 2', 'Portal Build'
};
List<String> cities = new List<String>{
    'Elgin', 'Toledo', 'Grand Rapids', 'Akron', 'Peoria', 'Dayton', 'Madison',
    'Fort Wayne', 'Rockford', 'Kalamazoo', 'Erie', 'Green Bay', 'Lansing', 'Canton'
};
List<String> states = new List<String>{
    'IL', 'OH', 'MI', 'OH', 'IL', 'OH', 'WI', 'IN', 'IL', 'MI', 'PA', 'WI', 'MI', 'OH'
};

// ---------------------------------------------------------------------------
// 7. Acme Manufacturing — the story the live demo runs on
// ---------------------------------------------------------------------------
Account acme = new Account(
    Name = 'Acme Manufacturing',
    AccountNumber = MARKER + 'ACME',
    Industry = validIndustries.contains('Manufacturing') ? 'Manufacturing' : null,
    Type = customerType,
    AnnualRevenue = 84000000,
    NumberOfEmployees = 620,
    Phone = '(312) 555-0140',
    Website = 'www.acme-manufacturing.example',
    BillingStreet = '1400 Foundry Road',
    BillingCity = 'Elgin',
    BillingState = 'IL',
    BillingPostalCode = '60120',
    BillingCountry = 'USA',
    Description = 'Fictional demo account for the DUG "Intro to Claude and Salesforce" session. ' +
                  'Customer since 2021, three sites, renewed twice. Annual platform renewal ' +
                  'currently in flight.',
    OwnerId = owners[0]
);

List<Account> accounts = new List<Account>{ acme };

for (Integer i = 0; i < FILLER_ACCOUNTS; i++) {
    // Pair prefix with suffix so that (prefix, suffix) never repeats AND the
    // suffixes stay spread across the whole list. Walking i/60 straight into the
    // suffix index would use only the first five suffixes for 249 accounts,
    // which would make the org ~60% manufacturing. The *11 stride fixes that;
    // 11 is coprime with 30, so the pairs stay unique.
    Integer prefixIdx = Math.mod(i, prefixes.size());
    Integer suffixIdx = Math.mod(prefixIdx * 11 + i / prefixes.size(), suffixes.size());
    String prefix = prefixes[prefixIdx];
    List<String> suf = suffixes[suffixIdx].split('\\|');
    Integer cityIdx = Math.mod(rnd[i], cities.size());
    // ~30% are prospects with no closed history; the rest are customers
    Boolean isProspect = Math.mod(rnd[i + 300], 100) < 30;

    accounts.add(new Account(
        Name = prefix + ' ' + suf[0],
        AccountNumber = MARKER + String.valueOf(i + 1).leftPad(4, '0'),
        Industry = validIndustries.contains(suf[1]) ? suf[1] : null,
        Type = isProspect ? prospectType : customerType,
        AnnualRevenue = (1 + Math.mod(rnd[i + 600], 400)) * 250000,
        NumberOfEmployees = 25 + Math.mod(rnd[i + 900], 4000),
        BillingCity = cities[cityIdx],
        BillingState = states[cityIdx],
        BillingCountry = 'USA',
        Description = 'Fictional filler account for the DUG demo org.',
        OwnerId = owners[Math.mod(rnd[i + 1200], owners.size())]
    ));
}
insert accounts;
System.debug('Inserted ' + accounts.size() + ' accounts.');

// ---------------------------------------------------------------------------
// 8. Contacts — five at Acme, one or two at each filler account
// ---------------------------------------------------------------------------
List<Contact> contacts = new List<Contact>{
    new Contact(
        AccountId = acme.Id, FirstName = 'Dana', LastName = 'Whitfield',
        Title = 'VP of Operations',
        Email = 'dana.whitfield@acme-manufacturing.example', Phone = '(312) 555-0152',
        Description = 'Joined Acme three weeks ago from a competitor in the same sector. No ' +
                      'relationship with us yet and has never been contacted. Now the primary ' +
                      'decision maker on the renewal.'
    ),
    new Contact(
        AccountId = acme.Id, FirstName = 'Marcus', LastName = 'Reyes',
        Title = 'Director of IT',
        Email = 'marcus.reyes@acme-manufacturing.example', Phone = '(312) 555-0147',
        Description = 'Long-time champion, our main contact since 2021. Opened the escalated ' +
                      'Line 3 defect case. Flagged the leadership change before going quiet.'
    ),
    new Contact(
        AccountId = acme.Id, FirstName = 'Priya', LastName = 'Raman',
        Title = 'Procurement Manager',
        Email = 'priya.raman@acme-manufacturing.example', Phone = '(312) 555-0149',
        Description = 'Owns the paperwork on the renewal. Wants the multi-year option priced.'
    ),
    new Contact(
        AccountId = acme.Id, FirstName = 'Alan', LastName = 'Voss',
        Title = 'Plant Manager, Elgin',
        Email = 'alan.voss@acme-manufacturing.example', Phone = '(312) 555-0161',
        Description = 'Runs the site where Line 3 keeps stopping. Most affected by the defect, ' +
                      'least happy with us right now.'
    ),
    new Contact(
        AccountId = acme.Id, FirstName = 'Teresa', LastName = 'Nunez',
        Title = 'CFO',
        Email = 'teresa.nunez@acme-manufacturing.example', Phone = '(312) 555-0155',
        Description = 'Signs the renewal. Has asked twice what we are doing about the outages.'
    )
};

// Track which contact belongs to which filler account for activity linking
Map<Id, Id> primaryContactByAccount = new Map<Id, Id>();
List<Integer> contactAccountIdx = new List<Integer>();   // index into accounts, parallel to the
                                                         // filler contacts appended below

for (Integer i = 0; i < FILLER_ACCOUNTS; i++) {
    Integer acctIdx = i + 1;   // accounts[0] is Acme
    Integer fnIdx = Math.mod(rnd[i + 1500], firstNames.size());
    Integer lnIdx = Math.mod(rnd[i + 1800], lastNames.size());
    String fn = firstNames[fnIdx];
    String ln = lastNames[lnIdx];

    contacts.add(new Contact(
        AccountId = accounts[acctIdx].Id,
        FirstName = fn, LastName = ln,
        Title = titles[Math.mod(rnd[i + 2100], titles.size())],
        Email = fn.toLowerCase() + '.' + ln.toLowerCase().replace('-', '') + i + '@example.com'
    ));
    contactAccountIdx.add(acctIdx);

    // ~55% of accounts get a second contact
    if (Math.mod(rnd[i + 2400], 100) < 55) {
        Integer fn2 = Math.mod(rnd[i + 2700], firstNames.size());
        Integer ln2 = Math.mod(rnd[i + 3000], lastNames.size());
        contacts.add(new Contact(
            AccountId = accounts[acctIdx].Id,
            FirstName = firstNames[fn2], LastName = lastNames[ln2],
            Title = titles[Math.mod(rnd[i + 3300], titles.size())],
            Email = firstNames[fn2].toLowerCase() + '.' +
                    lastNames[ln2].toLowerCase().replace('-', '') + i + 'b@example.com'
        ));
        contactAccountIdx.add(acctIdx);
    }
}
insert contacts;
System.debug('Inserted ' + contacts.size() + ' contacts.');

// First contact created for each account, for linking activities to a person
for (Integer c = 5; c < contacts.size(); c++) {
    Id acctId = accounts[contactAccountIdx[c - 5]].Id;
    if (!primaryContactByAccount.containsKey(acctId)) {
        primaryContactByAccount.put(acctId, contacts[c].Id);
    }
}
Contact marcusIt = contacts[1];
Contact alanPlant = contacts[3];

// ---------------------------------------------------------------------------
// 9. Opportunities
//
//    THE ONE INVARIANT THAT MATTERS: no stale open deal closing this quarter
//    may be worth more than Acme's $250K, or Acme stops topping the slide 22
//    "quiet deals by amount" query. Amounts are clamped below to enforce it.
// ---------------------------------------------------------------------------
Date acmeClose = qEnd.addDays(-2);
if (acmeClose <= today) acmeClose = qEnd;

Opportunity acmeRenewal = new Opportunity(
    AccountId = acme.Id,
    Name = 'Acme Manufacturing - Annual Platform Renewal',
    Amount = 250000, CloseDate = acmeClose,
    StageName = validStages.contains('Negotiation/Review') ? 'Negotiation/Review' : openStages[0],
    Type = upgradeType, Probability = 60,
    NextStep = 'Confirm renewal terms with procurement',
    Description = 'Annual platform renewal, third term. Quiet for three weeks. The new VP of ' +
                  'Operations has not been briefed and there is an escalated defect case open ' +
                  'on the account.',
    OwnerId = owners[0]
);
// Open, fresh and smaller — safe to sit alongside the renewal without displacing it
Opportunity acmeExpansion = new Opportunity(
    AccountId = acme.Id,
    Name = 'Acme Manufacturing - Line 4 Sensor Package',
    Amount = 40000, CloseDate = qEnd,
    StageName = validStages.contains('Qualification') ? 'Qualification' : openStages[0],
    Type = upgradeType, Probability = 20,
    NextStep = 'Waiting on Line 3 fix before Alan will discuss Line 4',
    Description = 'Expansion opportunity for the fourth production line. Explicitly blocked on ' +
                  'resolving the Line 3 firmware defect.',
    OwnerId = owners[0]
);

List<Opportunity> opps = new List<Opportunity>{ acmeRenewal, acmeExpansion };

// Acme history: two won renewals and one lost expansion, for trend questions
if (wonStage != null) {
    opps.add(new Opportunity(
        AccountId = acme.Id, Name = 'Acme Manufacturing - Renewal (prior term)',
        Amount = 225000, CloseDate = today.addMonths(-12).toStartOfMonth().addDays(14),
        StageName = wonStage, Type = upgradeType, OwnerId = owners[0],
        Description = 'Renewed without friction. No escalations open at the time.'
    ));
    opps.add(new Opportunity(
        AccountId = acme.Id, Name = 'Acme Manufacturing - Initial Platform Purchase',
        Amount = 180000, CloseDate = today.addMonths(-24).toStartOfMonth().addDays(9),
        StageName = wonStage, Type = newCustType, OwnerId = owners[0],
        Description = 'Original land. Two sites, 200 seats.'
    ));
}
if (lostStage != null) {
    opps.add(new Opportunity(
        AccountId = acme.Id, Name = 'Acme Manufacturing - Warehouse Module',
        Amount = 65000, CloseDate = today.addMonths(-7).toStartOfMonth().addDays(20),
        StageName = lostStage, Type = upgradeType, OwnerId = owners[0],
        Description = 'Lost to an incumbent WMS vendor. Budget cited.'
    ));
}

// Filler opportunities. Records which list index is a current open deal so the
// activity loop below can give the open ones a realistic recency spread.
List<Integer> openOppIdx = new List<Integer>();
List<Integer> openOppStaleDays = new List<Integer>();
List<Integer> openOppAcctIdx = new List<Integer>();
List<Integer> closedOppIdx = new List<Integer>();
List<Integer> closedOppAcctIdx = new List<Integer>();

for (Integer i = 0; i < FILLER_ACCOUNTS; i++) {
    Integer acctIdx = i + 1;
    Id ownerId = accounts[acctIdx].OwnerId;
    String label = dealLabels[Math.mod(rnd[i + 3600], dealLabels.size())];
    String acctName = accounts[acctIdx].Name;

    // Amount tiers: mostly modest deals, a few large ones
    Integer tier = Math.mod(rnd[i], 100);
    Integer amount;
    if (tier < 45)      amount = 10000  + Math.mod(rnd[i + 3900], 40)  * 1000;
    else if (tier < 75) amount = 50000  + Math.mod(rnd[i + 3900], 50)  * 1000;
    else if (tier < 92) amount = 100000 + Math.mod(rnd[i + 3900], 100) * 1000;
    else                amount = 200000 + Math.mod(rnd[i + 3900], 200) * 1000;

    Integer disposition = Math.mod(rnd[i + 4200], 100);
    Integer staleDays = Math.mod(rnd[i + 4500], 45);   // 0-44 days since last touch

    if (disposition < 40) {
        // Open, closing THIS quarter — the set the demo queries hit
        if (staleDays > 14 && amount >= 250000) {
            // Must stay under Acme's $250K or Acme loses the top of the slide 22
            // list. Spread across $180K-$239K rather than pinned to one value:
            // half a dozen deals showing an identical amount looks synthetic on
            // a projector, which is the one place this data gets scrutinised.
            amount = 180000 + Math.mod(rnd[i + 6000], 60) * 1000;
        }
        Date closeDate = today.addDays(1 + Math.mod(rnd[i + 4800], daysLeftInQuarter));
        if (closeDate > qEnd) closeDate = qEnd;
        opps.add(new Opportunity(
            AccountId = accounts[acctIdx].Id,
            Name = acctName + ' - ' + label,
            Amount = amount, CloseDate = closeDate,
            StageName = openStages[Math.mod(rnd[i + 5100], openStages.size())],
            Type = accounts[acctIdx].Type == prospectType ? newCustType : upgradeType,
            OwnerId = ownerId
        ));
        openOppIdx.add(opps.size() - 1);
        openOppStaleDays.add(staleDays);
        openOppAcctIdx.add(acctIdx);

    } else if (disposition < 62) {
        // Open, closing in a LATER quarter — pipeline beyond the current window
        opps.add(new Opportunity(
            AccountId = accounts[acctIdx].Id,
            Name = acctName + ' - ' + label,
            Amount = amount, CloseDate = qEnd.addDays(10 + Math.mod(rnd[i + 4800], 150)),
            StageName = openStages[Math.mod(rnd[i + 5100], openStages.size())],
            Type = accounts[acctIdx].Type == prospectType ? newCustType : upgradeType,
            OwnerId = ownerId
        ));
        openOppIdx.add(opps.size() - 1);
        openOppStaleDays.add(staleDays);
        openOppAcctIdx.add(acctIdx);

    } else if (wonStage != null && lostStage != null) {
        // Closed in a past quarter
        Boolean won = Math.mod(rnd[i + 5400], 100) < 64;   // ~64% win rate
        opps.add(new Opportunity(
            AccountId = accounts[acctIdx].Id,
            Name = acctName + ' - ' + label,
            Amount = amount,
            CloseDate = today.addDays(-(20 + Math.mod(rnd[i + 4800], 700))),
            StageName = won ? wonStage : lostStage,
            Type = accounts[acctIdx].Type == prospectType ? newCustType : upgradeType,
            OwnerId = ownerId
        ));
        closedOppIdx.add(opps.size() - 1);
        closedOppAcctIdx.add(acctIdx);
    }

    // ~40% of accounts carry an extra piece of closed history
    if (wonStage != null && lostStage != null && Math.mod(rnd[i + 5700], 100) < 40) {
        Boolean won2 = Math.mod(rnd[i + 2100], 100) < 64;
        opps.add(new Opportunity(
            AccountId = accounts[acctIdx].Id,
            Name = acctName + ' - ' + dealLabels[Math.mod(rnd[i + 900], dealLabels.size())],
            Amount = 8000 + Math.mod(rnd[i + 1200], 90) * 1000,
            CloseDate = today.addDays(-(120 + Math.mod(rnd[i + 600], 600))),
            StageName = won2 ? wonStage : lostStage,
            Type = upgradeType, OwnerId = ownerId
        ));
        closedOppIdx.add(opps.size() - 1);
        closedOppAcctIdx.add(acctIdx);
    }
}
insert opps;
System.debug('Inserted ' + opps.size() + ' opportunities (' + openOppIdx.size() +
             ' open, ' + closedOppIdx.size() + ' closed history).');

// ---------------------------------------------------------------------------
// 10. Activity history. This is what drives LastActivityDate, and therefore the
//     "no activity in the last 14 days" query. Only COMPLETED tasks roll up.
// ---------------------------------------------------------------------------
List<Task> tasks = new List<Task>();
List<Event> events = new List<Event>();

// Acme's timeline: last touch 23 days ago, so "quiet for three weeks" is true
tasks.add(new Task(
    WhatId = acmeRenewal.Id, WhoId = marcusIt.Id, OwnerId = owners[0],
    Subject = 'Call', Status = doneStatus, Priority = 'Normal',
    ActivityDate = today.addDays(-23),
    Description = 'Renewal check-in with Marcus. He flagged the Line 3 faults and mentioned a ' +
                  'new VP of Operations was starting. Said he would loop us in. Nothing since.'
));
tasks.add(new Task(
    WhatId = acmeRenewal.Id, WhoId = marcusIt.Id, OwnerId = owners[0],
    Subject = 'Email', Status = doneStatus, Priority = 'Normal',
    ActivityDate = today.addDays(-31),
    Description = 'Sent renewal quote with single-year and three-year options.'
));
tasks.add(new Task(
    WhatId = acme.Id, WhoId = alanPlant.Id, OwnerId = owners[0],
    Subject = 'Call', Status = doneStatus, Priority = 'High',
    ActivityDate = today.addDays(-38),
    Description = 'Alan called about the second Line 3 stoppage. Unhappy. Asked what the ' +
                  'escalation path is. Promised him an update from engineering.'
));
tasks.add(new Task(
    WhatId = acmeRenewal.Id, OwnerId = owners[0],
    Subject = 'Email', Status = doneStatus, Priority = 'Normal',
    ActivityDate = today.addDays(-52),
    Description = 'Renewal timeline agreed with Priya in procurement.'
));
tasks.add(new Task(
    WhatId = acme.Id, OwnerId = owners[0],
    Subject = 'Email', Status = doneStatus, Priority = 'Normal',
    ActivityDate = today.addDays(-74),
    Description = 'Quarterly business review scheduling thread.'
));
events.add(new Event(
    WhatId = acme.Id, WhoId = marcusIt.Id, OwnerId = owners[0],
    Subject = 'Quarterly business review',
    StartDateTime = DateTime.newInstance(today.addDays(-67), Time.newInstance(14, 0, 0, 0)),
    EndDateTime = DateTime.newInstance(today.addDays(-67), Time.newInstance(15, 0, 0, 0)),
    Description = 'Q review with Marcus and Teresa. Adoption strong on Lines 1 and 2. ' +
                  'Line 3 firmware raised as a watch item.'
));

// Open deals: the most recent completed task lands exactly on the deal's
// staleDays, with one or two older ones behind it so timelines look lived-in.
for (Integer k = 0; k < openOppIdx.size(); k++) {
    Integer oIdx = openOppIdx[k];
    Integer staleDays = openOppStaleDays[k];
    Id acctId = accounts[openOppAcctIdx[k]].Id;
    Id ownerId = opps[oIdx].OwnerId;
    Id whoId = primaryContactByAccount.get(acctId);

    tasks.add(new Task(
        WhatId = opps[oIdx].Id, WhoId = whoId, OwnerId = ownerId,
        Subject = Math.mod(k, 2) == 0 ? 'Call' : 'Email',
        Status = doneStatus, Priority = 'Normal',
        ActivityDate = today.addDays(-staleDays)
    ));
    tasks.add(new Task(
        WhatId = opps[oIdx].Id, WhoId = whoId, OwnerId = ownerId,
        Subject = 'Email', Status = doneStatus, Priority = 'Normal',
        ActivityDate = today.addDays(-(staleDays + 12 + Math.mod(rnd[k], 20)))
    ));
    // ~35% also had a meeting
    if (Math.mod(rnd[k + 300], 100) < 35) {
        Date evDate = today.addDays(-(staleDays + 4 + Math.mod(rnd[k + 600], 10)));
        events.add(new Event(
            WhatId = opps[oIdx].Id, WhoId = whoId, OwnerId = ownerId,
            Subject = 'Discovery call',
            StartDateTime = DateTime.newInstance(evDate, Time.newInstance(10, 0, 0, 0)),
            EndDateTime = DateTime.newInstance(evDate, Time.newInstance(10, 45, 0, 0))
        ));
    }
}

// Closed deals get a single closing-note task, dated around the close
for (Integer k = 0; k < closedOppIdx.size(); k++) {
    Integer oIdx = closedOppIdx[k];
    tasks.add(new Task(
        WhatId = opps[oIdx].Id,
        WhoId = primaryContactByAccount.get(accounts[closedOppAcctIdx[k]].Id),
        OwnerId = opps[oIdx].OwnerId,
        Subject = 'Email', Status = doneStatus, Priority = 'Normal',
        ActivityDate = opps[oIdx].CloseDate.addDays(-2),
        Description = opps[oIdx].StageName == wonStage
            ? 'Signed. Handed off to onboarding.'
            : 'Closed out. No decision this cycle.'
    ));
}
insert tasks;
insert events;

// ---------------------------------------------------------------------------
// 11. Summary
// ---------------------------------------------------------------------------
System.debug('=====================================================');
System.debug('01 core load complete — ' + thisOrg.Name);
System.debug('  Accounts:      ' + accounts.size());
System.debug('  Contacts:      ' + contacts.size());
System.debug('  Opportunities: ' + opps.size());
System.debug('  Tasks:         ' + tasks.size());
System.debug('  Events:        ' + events.size());
System.debug('  TOTAL:         ' + (accounts.size() + contacts.size() + opps.size() +
                                    tasks.size() + events.size()));
System.debug('  Owners used:   ' + owners.size());
System.debug('  Acme renewal closes ' + acmeClose + ' for $250,000, last touch ' +
             today.addDays(-23));
System.debug('');
System.debug('NEXT: run 02_load_service.apex, then 03, then 04, then 05_verify_demo.apex.');
System.debug('=====================================================');
