/* =============================================================================
 * Intro to Claude and Salesforce — DUG demo data loader
 * Run in: Developer Console -> Debug -> Open Execute Anonymous Window
 *
 * Idempotent: every record it creates is tagged with AccountNumber 'DUG-DEMO-*'
 * and wiped at the top of this script, so you can re-run it as many times as
 * you like (e.g. before Wednesday's run-through) without piling up duplicates.
 *
 * Creates:
 *   - Acme Manufacturing: $250K renewal, quiet 3+ weeks, escalated defect case,
 *     brand-new VP of Operations
 *   - 18 filler accounts with contacts, opportunities and activity history
 *   - A deliberate mix of stale / fresh activity so the "no activity in 14 days"
 *     query returns something interesting with Acme at the top by amount
 *
 * After running this, run 02_verify_demo.apex in a SEPARATE execution — the
 * LastActivityDate rollup is computed by the platform after this transaction
 * commits, so it reads as null if you query it inline here.
 * ============================================================================= */

// ---------------------------------------------------------------------------
// 0. Safety rail — never let this touch a real org
// ---------------------------------------------------------------------------
Organization thisOrg = [SELECT Id, Name, IsSandbox, OrganizationType FROM Organization LIMIT 1];
Boolean orgIsSafe = thisOrg.IsSandbox || thisOrg.OrganizationType == 'Developer Edition';
System.assert(
    orgIsSafe,
    'REFUSING TO RUN. This looks like a production org: "' + thisOrg.Name +
    '" (' + thisOrg.OrganizationType + '). Load demo data into a Developer Edition org ' +
    'or a sandbox only. If you really mean to run here, delete this assert block.'
);

final String MARKER = 'DUG-DEMO-';
final String MARKER_LIKE = MARKER + '%';   // SOQL binds need a plain variable

// ---------------------------------------------------------------------------
// 1. Wipe any previous run (Account delete cascades to its contacts,
//    opportunities, cases and activities)
// ---------------------------------------------------------------------------
List<Account> priorRun = [SELECT Id FROM Account WHERE AccountNumber LIKE :MARKER_LIKE];
if (!priorRun.isEmpty()) {
    delete priorRun;
    Database.emptyRecycleBin(priorRun);
    System.debug('Cleaned up ' + priorRun.size() + ' account(s) from a previous run.');
}

// ---------------------------------------------------------------------------
// 2. Picklist safety — fall back gracefully if this org's picklists differ
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
Set<String> validCaseStatus = new Set<String>();
for (Schema.PicklistEntry pe : Case.Status.getDescribe().getPicklistValues()) {
    if (pe.isActive()) validCaseStatus.add(pe.getValue());
}
Set<String> validCaseTypes = new Set<String>();
for (Schema.PicklistEntry pe : Case.Type.getDescribe().getPicklistValues()) {
    if (pe.isActive()) validCaseTypes.add(pe.getValue());
}
Set<String> validTaskStatus = new Set<String>();
for (Schema.PicklistEntry pe : Task.Status.getDescribe().getPicklistValues()) {
    if (pe.isActive()) validTaskStatus.add(pe.getValue());
}
Set<String> validAccountTypes = new Set<String>();
for (Schema.PicklistEntry pe : Account.Type.getDescribe().getPicklistValues()) {
    if (pe.isActive()) validAccountTypes.add(pe.getValue());
}
String customerType = validAccountTypes.contains('Customer - Direct') ? 'Customer - Direct' : null;
Set<String> validCaseOrigins = new Set<String>();
for (Schema.PicklistEntry pe : Case.Origin.getDescribe().getPicklistValues()) {
    if (pe.isActive()) validCaseOrigins.add(pe.getValue());
}

String fallbackStage = validStages.contains('Prospecting')
    ? 'Prospecting'
    : new List<String>(validStages)[0];
// LastActivityDate only rolls up from COMPLETED tasks, so this value matters.
String doneStatus = validTaskStatus.contains('Completed')
    ? 'Completed'
    : new List<String>(validTaskStatus)[0];

// ---------------------------------------------------------------------------
// 3. Owners — the running user gets Acme plus a chunk of the pipeline so
//    "which of MY opportunities..." works; the rest spread across other users
//    so the dashboard's "filter by owner" has something to filter.
// ---------------------------------------------------------------------------
List<Id> owners = new List<Id>{ UserInfo.getUserId() };
for (User u : [
    SELECT Id FROM User
    WHERE IsActive = true AND UserType = 'Standard' AND Id != :UserInfo.getUserId()
    ORDER BY CreatedDate ASC
    LIMIT 3
]) {
    owners.add(u.Id);
}
if (owners.size() == 1) {
    System.debug(LoggingLevel.WARN,
        '*** Only one active standard user in this org, so every opportunity will be yours. ' +
        'The "filter by owner" part of the dashboard demo (slide 22, prompt 4) will look flat. ' +
        'Create 2-3 extra users first if you want that to land. ***');
}

// ---------------------------------------------------------------------------
// 4. Dates — everything is relative to today, so this stays correct whenever
//    you re-run it. "This quarter" here means the CALENDAR quarter; if your org
//    uses a custom fiscal year, SOQL's THIS_QUARTER follows the fiscal calendar
//    instead and you may need to shift these close dates.
// ---------------------------------------------------------------------------
Date today = Date.today();
Integer qIndex = (today.month() - 1) / 3;
Date qStart = Date.newInstance(today.year(), qIndex * 3 + 1, 1);
Date qEnd = qStart.addMonths(3).addDays(-1);
Integer daysLeftInQuarter = Math.max(today.daysBetween(qEnd), 1);

System.debug('Loading demo data. Quarter: ' + qStart + ' to ' + qEnd +
             ' (' + daysLeftInQuarter + ' days left).');

// ---------------------------------------------------------------------------
// 5. Filler data
//    Format: Account | Industry | Opportunity | Amount | Stage | DaysSinceLastActivity | OwnerIndex
//    OwnerIndex 0 is you. DaysSinceLastActivity > 14 makes the deal show up as
//    "at risk" in the slide 22 demo.
// ---------------------------------------------------------------------------
List<String> fillerRows = new List<String>{
    'Northgate Fabrication|Manufacturing|Northgate - Line Expansion|310000|Proposal/Price Quote|3|0',
    'Harbor Point Logistics|Transportation|Harbor Point - Fleet Telemetry|185000|Negotiation/Review|26|0',
    'Cedar Ridge Health Partners|Healthcare|Cedar Ridge - Clinic Rollout|120000|Value Proposition|19|0',
    'Vantage Grid Utilities|Utilities|Vantage Grid - Meter Program|95000|Needs Analysis|33|0',
    'Bluefield Insurance Group|Insurance|Bluefield - Claims Modernization|60000|Qualification|22|0',
    'Sable Creek Foods|Food & Beverage|Sable Creek - Retail Pilot|48000|Prospecting|5|0',
    'Ironwood Construction|Construction|Ironwood - Site Safety Rollout|142000|Proposal/Price Quote|2|1',
    // Deliberately under Acme's $250K: this one is stale too, and if the org has
    // only one user it lands in your pipeline, where anything larger would knock
    // Acme off the top of the slide 22 "quiet deals by amount" query.
    'Lakeside Financial|Banking|Lakeside - Advisor Portal|215000|Negotiation/Review|17|1',
    'Pioneer Ag Supply|Agriculture|Pioneer - Dealer Network|88000|Value Proposition|9|1',
    'Summit Ridge Education|Education|Summit Ridge - Campus Licensing|54000|Needs Analysis|31|1',
    'Copper Lane Retail|Retail|Copper Lane - Store Ops|67000|Qualification|4|2',
    'Meridian Biotech|Biotechnology|Meridian - Lab Data Platform|198000|Proposal/Price Quote|12|2',
    'Fairmont Hospitality|Hospitality|Fairmont - Property Rollout|73000|Prospecting|28|2',
    'Redstone Mineral Group|Energy|Redstone - Equipment Refresh|156000|Negotiation/Review|6|2',
    'Orchard Park Media|Media|Orchard Park - Ad Ops|39000|Qualification|15|3',
    'Talon Security Systems|Technology|Talon - Managed Detection|112000|Value Proposition|8|3',
    'Willow Bend Senior Living|Healthcare|Willow Bend - Care Coordination|81000|Needs Analysis|24|3',
    'Kestrel Aerospace|Manufacturing|Kestrel - Parts Traceability|230000|Proposal/Price Quote|1|3'
};

// Index-matched to fillerRows. Format: First | Last | Title
List<String> fillerContacts = new List<String>{
    'Amara|Osei|Director of Operations',
    'Devon|Pryce|VP Logistics',
    'Lucia|Ferrante|Chief Nursing Officer',
    'Bennett|Shaw|Grid Operations Manager',
    'Rina|Kapoor|Claims Director',
    'Tomas|Delgado|Category Manager',
    'Gwen|Halloway|Safety Director',
    'Isaiah|Brandt|Head of Digital',
    'Marta|Kowalski|Dealer Programs Lead',
    'Owen|Tanaka|CIO',
    'Simone|Achebe|Director of Store Systems',
    'Felix|Arnaud|Head of Research Informatics',
    'Nadia|Rostami|Regional GM',
    'Curtis|Vale|Maintenance Director',
    'Elena|Sorokin|Ad Operations Manager',
    'Jae|Min|Security Operations Lead',
    'Harriet|Boyle|Director of Care Quality',
    'Ravi|Chandrasekar|Quality Systems Manager'
};
System.assert(
    fillerRows.size() == fillerContacts.size(),
    'fillerRows (' + fillerRows.size() + ') and fillerContacts (' + fillerContacts.size() +
    ') must stay index-matched. Add or remove a row from both lists.'
);

// ---------------------------------------------------------------------------
// 6. Accounts
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
                  'Customer since 2021. Annual platform renewal in flight.',
    OwnerId = owners[0]
);

List<Account> accounts = new List<Account>{ acme };
for (Integer i = 0; i < fillerRows.size(); i++) {
    List<String> f = fillerRows[i].split('\\|');
    accounts.add(new Account(
        Name = f[0],
        AccountNumber = MARKER + String.valueOf(i + 1).leftPad(2, '0'),
        Industry = validIndustries.contains(f[1]) ? f[1] : null,
        Type = customerType,
        Description = 'Fictional filler account for the DUG demo org.',
        OwnerId = owners[Math.mod(Integer.valueOf(f[6]), owners.size())]
    ));
}
insert accounts;

// ---------------------------------------------------------------------------
// 7. Contacts — Acme gets three, including the brand-new VP of Operations
//    who is the target of the slide 22 "Act" prompt.
// ---------------------------------------------------------------------------
List<Contact> contacts = new List<Contact>{
    new Contact(
        AccountId = acme.Id,
        FirstName = 'Dana',
        LastName = 'Whitfield',
        Title = 'VP of Operations',
        Email = 'dana.whitfield@acme-manufacturing.example',
        Phone = '(312) 555-0152',
        Description = 'Joined Acme three weeks ago. No relationship with us yet — has not been ' +
                      'contacted since the leadership change. Primary decision maker on the renewal.'
    ),
    new Contact(
        AccountId = acme.Id,
        FirstName = 'Marcus',
        LastName = 'Reyes',
        Title = 'Director of IT',
        Email = 'marcus.reyes@acme-manufacturing.example',
        Phone = '(312) 555-0147',
        Description = 'Long-time champion. Opened the escalated defect case.'
    ),
    new Contact(
        AccountId = acme.Id,
        FirstName = 'Priya',
        LastName = 'Raman',
        Title = 'Procurement Manager',
        Email = 'priya.raman@acme-manufacturing.example',
        Phone = '(312) 555-0149',
        Description = 'Owns the paperwork on the renewal.'
    )
};
for (Integer i = 0; i < fillerRows.size(); i++) {
    List<String> c = fillerContacts[i].split('\\|');
    contacts.add(new Contact(
        AccountId = accounts[i + 1].Id,   // +1 because accounts[0] is Acme
        FirstName = c[0],
        LastName = c[1],
        Title = c[2],
        Email = c[0].toLowerCase() + '.' + c[1].toLowerCase() + '@example.com'
    ));
}
insert contacts;

Contact marcusIt = contacts[1];   // opened the escalated case

// ---------------------------------------------------------------------------
// 8. Opportunities
// ---------------------------------------------------------------------------
Date acmeClose = qEnd.addDays(-2);
if (acmeClose <= today) acmeClose = qEnd;

Opportunity acmeRenewal = new Opportunity(
    AccountId = acme.Id,
    Name = 'Acme Manufacturing - Annual Platform Renewal',
    Amount = 250000,
    CloseDate = acmeClose,
    StageName = validStages.contains('Negotiation/Review') ? 'Negotiation/Review' : fallbackStage,
    Type = validOppTypes.contains('Existing Customer - Upgrade') ? 'Existing Customer - Upgrade' : null,
    Probability = 60,
    NextStep = 'Confirm renewal terms with procurement',
    Description = 'Annual platform renewal. Quiet for three weeks. New VP of Operations has not ' +
                  'been briefed and there is an escalated defect case open on the account.',
    OwnerId = owners[0]
);

List<Opportunity> opps = new List<Opportunity>{ acmeRenewal };
Map<Integer, Integer> oppRowIndex = new Map<Integer, Integer>();  // opps index -> fillerRows index

for (Integer i = 0; i < fillerRows.size(); i++) {
    List<String> f = fillerRows[i].split('\\|');
    Date closeDate = today.addDays(1 + Math.mod(i * 5, daysLeftInQuarter));
    if (closeDate > qEnd) closeDate = qEnd;

    opps.add(new Opportunity(
        AccountId = accounts[i + 1].Id,
        Name = f[2],
        Amount = Decimal.valueOf(f[3]),
        CloseDate = closeDate,
        StageName = validStages.contains(f[4]) ? f[4] : fallbackStage,
        Type = validOppTypes.contains('New Customer') ? 'New Customer' : null,
        OwnerId = owners[Math.mod(Integer.valueOf(f[6]), owners.size())]
    ));
    oppRowIndex.put(opps.size() - 1, i);
}

// Two closed deals so the pipeline-by-stage chart isn't all open pipeline
if (validStages.contains('Closed Won')) {
    opps.add(new Opportunity(
        AccountId = accounts[1].Id,
        Name = 'Northgate - Q3 Add-On Licenses',
        Amount = 45000,
        CloseDate = today.addDays(-12),
        StageName = 'Closed Won',
        OwnerId = owners[0]
    ));
}
if (validStages.contains('Closed Lost')) {
    opps.add(new Opportunity(
        AccountId = accounts[5].Id,
        Name = 'Bluefield - Analytics Bundle',
        Amount = 32000,
        CloseDate = today.addDays(-20),
        StageName = 'Closed Lost',
        OwnerId = owners[Math.mod(1, owners.size())]
    ));
}
insert opps;

// ---------------------------------------------------------------------------
// 9. Cases — Acme's escalated defect is the one that matters. Note: Salesforce
//    won't let Apex backdate CreatedDate outside of tests, so every case here
//    shows as created today. The age is written into the subject/description so
//    Claude still has it to work with on screen.
// ---------------------------------------------------------------------------
String escalatedStatus = validCaseStatus.contains('Escalated')
    ? 'Escalated'
    : (validCaseStatus.contains('Working') ? 'Working' : new List<String>(validCaseStatus)[0]);
String problemType = validCaseTypes.contains('Problem') ? 'Problem' : null;

List<Case> cases = new List<Case>{
    new Case(
        AccountId = acme.Id,
        ContactId = marcusIt.Id,
        Subject = 'Conveyor controller firmware defect halting Line 3 (open 12 days)',
        Status = escalatedStatus,
        Priority = 'High',
        Type = problemType,
        Origin = validCaseOrigins.contains('Phone') ? 'Phone' : null,
        IsEscalated = true,
        Description = 'Firmware release 4.2 causes intermittent controller faults on Line 3. ' +
                      'Acme has had two unplanned stoppages. Escalated after the second incident. ' +
                      'Engineering has a patch in QA, no committed ship date. Reported 12 days ago.'
    ),
    new Case(
        AccountId = accounts[2].Id,
        Subject = 'Telemetry dashboard loading slowly for dispatch team',
        Status = validCaseStatus.contains('Working') ? 'Working' : escalatedStatus,
        Priority = 'Medium',
        Type = problemType,
        Origin = 'Email'
    ),
    new Case(
        AccountId = accounts[8].Id,
        Subject = 'SSO login loop for three advisor accounts',
        Status = validCaseStatus.contains('Working') ? 'Working' : escalatedStatus,
        Priority = 'High',
        Type = problemType,
        Origin = 'Web'
    ),
    new Case(
        AccountId = accounts[12].Id,
        Subject = 'Request: add export to the lab data report',
        Status = validCaseStatus.contains('New') ? 'New' : escalatedStatus,
        Priority = 'Low',
        Type = validCaseTypes.contains('Feature Request') ? 'Feature Request' : problemType,
        Origin = 'Email'
    )
};
insert cases;

// ---------------------------------------------------------------------------
// 10. Activity history — this is what actually drives LastActivityDate and
//     therefore the "no activity in the last 14 days" query on slide 22.
//     Only COMPLETED tasks roll up, so these are all completed.
// ---------------------------------------------------------------------------
List<Task> tasks = new List<Task>();

// Acme: last touch 23 days ago -> comfortably "quiet for three weeks"
tasks.add(new Task(
    WhatId = acmeRenewal.Id, WhoId = marcusIt.Id, OwnerId = owners[0],
    Subject = 'Call', Status = doneStatus, Priority = 'Normal',
    ActivityDate = today.addDays(-23),
    Description = 'Renewal check-in with Marcus. He flagged the Line 3 faults and said ' +
                  'a new VP of Operations was starting. Said he would loop us in. Nothing since.'
));
tasks.add(new Task(
    WhatId = acmeRenewal.Id, WhoId = marcusIt.Id, OwnerId = owners[0],
    Subject = 'Email', Status = doneStatus, Priority = 'Normal',
    ActivityDate = today.addDays(-41),
    Description = 'Sent renewal quote and multi-year options.'
));
tasks.add(new Task(
    WhatId = acme.Id, OwnerId = owners[0],
    Subject = 'Email', Status = doneStatus, Priority = 'Normal',
    ActivityDate = today.addDays(-58),
    Description = 'Quarterly business review scheduling thread.'
));

// Filler: most recent task lands exactly on the row's DaysSinceLastActivity,
// with an older one behind it so the timeline doesn't look synthetic.
for (Integer oppIdx : oppRowIndex.keySet()) {
    Integer rowIdx = oppRowIndex.get(oppIdx);
    List<String> f = fillerRows[rowIdx].split('\\|');
    Integer staleDays = Integer.valueOf(f[5]);
    Id ownerId = owners[Math.mod(Integer.valueOf(f[6]), owners.size())];

    tasks.add(new Task(
        WhatId = opps[oppIdx].Id, WhoId = contacts[rowIdx + 3].Id, OwnerId = ownerId,
        Subject = Math.mod(rowIdx, 2) == 0 ? 'Call' : 'Email',
        Status = doneStatus, Priority = 'Normal',
        ActivityDate = today.addDays(-staleDays)
    ));
    tasks.add(new Task(
        WhatId = opps[oppIdx].Id, WhoId = contacts[rowIdx + 3].Id, OwnerId = ownerId,
        Subject = 'Email',
        Status = doneStatus, Priority = 'Normal',
        ActivityDate = today.addDays(-(staleDays + 13 + Math.mod(rowIdx, 7)))
    ));
}
insert tasks;

// ---------------------------------------------------------------------------
// 11. Summary
// ---------------------------------------------------------------------------
System.debug('=====================================================');
System.debug('Demo data loaded into: ' + thisOrg.Name);
System.debug('  Accounts:      ' + accounts.size() + ' (Acme + ' + fillerRows.size() + ' filler)');
System.debug('  Contacts:      ' + contacts.size());
System.debug('  Opportunities: ' + opps.size());
System.debug('  Cases:         ' + cases.size());
System.debug('  Tasks:         ' + tasks.size());
System.debug('  Distinct owners used: ' + owners.size());
System.debug('  Acme renewal closes: ' + acmeClose + ' for $250,000');
System.debug('  Acme last activity:  ' + today.addDays(-23) + ' (23 days ago)');
System.debug('');
System.debug('NEXT: run 02_verify_demo.apex in a separate execution to confirm');
System.debug('the LastActivityDate rollup landed and the demo queries return data.');
System.debug('=====================================================');
