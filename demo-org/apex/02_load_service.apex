/* =============================================================================
 * DUG demo org — 02: service records
 * Cases and case comments. Run AFTER 01_load_core.apex.
 *
 * Acme gets a real case history rather than a single case: the escalated Line 3
 * firmware defect the demo hinges on, plus closed cases behind it so the account
 * reads like a relationship with a past. Roughly 90 cases across the org.
 * ============================================================================= */

Organization thisOrg = [SELECT Id, Name, IsSandbox, OrganizationType FROM Organization LIMIT 1];
System.assert(
    thisOrg.IsSandbox || thisOrg.OrganizationType == 'Developer Edition',
    'REFUSING TO RUN. Not a Developer Edition org or sandbox: "' + thisOrg.Name + '".'
);

final String MARKER_LIKE = 'DUG-DEMO-%';
Date today = Date.today();

// ---------------------------------------------------------------------------
// 1. Find the accounts 01 created, and wipe any cases from a previous 02 run
// ---------------------------------------------------------------------------
List<Account> demoAccounts = [
    SELECT Id, Name FROM Account WHERE AccountNumber LIKE :MARKER_LIKE ORDER BY AccountNumber
];
System.assert(
    !demoAccounts.isEmpty(),
    'No demo accounts found. Run 01_load_core.apex first.'
);
Set<Id> demoAcctIds = new Map<Id, Account>(demoAccounts).keySet();

List<Case> priorCases = [SELECT Id FROM Case WHERE AccountId IN :demoAcctIds];
if (!priorCases.isEmpty()) {
    delete priorCases;
    Database.emptyRecycleBin(priorCases);
    System.debug('Removed ' + priorCases.size() + ' case(s) from a previous run.');
}

// ---------------------------------------------------------------------------
// 2. Picklist safety
// ---------------------------------------------------------------------------
Set<String> validStatus = new Set<String>();
for (Schema.PicklistEntry pe : Case.Status.getDescribe().getPicklistValues()) {
    if (pe.isActive()) validStatus.add(pe.getValue());
}
Set<String> validTypes = new Set<String>();
for (Schema.PicklistEntry pe : Case.Type.getDescribe().getPicklistValues()) {
    if (pe.isActive()) validTypes.add(pe.getValue());
}
Set<String> validOrigins = new Set<String>();
for (Schema.PicklistEntry pe : Case.Origin.getDescribe().getPicklistValues()) {
    if (pe.isActive()) validOrigins.add(pe.getValue());
}
Set<String> validReasons = new Set<String>();
for (Schema.PicklistEntry pe : Case.Reason.getDescribe().getPicklistValues()) {
    if (pe.isActive()) validReasons.add(pe.getValue());
}

String sEscalated = validStatus.contains('Escalated') ? 'Escalated'
    : (validStatus.contains('Working') ? 'Working' : new List<String>(validStatus)[0]);
String sWorking = validStatus.contains('Working') ? 'Working' : sEscalated;
String sNew     = validStatus.contains('New') ? 'New' : sWorking;
String sClosed  = validStatus.contains('Closed') ? 'Closed' : sWorking;

String tProblem = validTypes.contains('Problem') ? 'Problem' : null;
String tQuestion = validTypes.contains('Question') ? 'Question' : tProblem;
String tFeature = validTypes.contains('Feature Request') ? 'Feature Request' : tProblem;

String oPhone = validOrigins.contains('Phone') ? 'Phone' : null;
String oEmail = validOrigins.contains('Email') ? 'Email' : null;
String oWeb   = validOrigins.contains('Web') ? 'Web' : null;
String rBreak = validReasons.contains('Breakdown') ? 'Breakdown' : null;

// ---------------------------------------------------------------------------
// 3. Acme's case history
// ---------------------------------------------------------------------------
Account acme;
for (Account a : demoAccounts) {
    if (a.Name == 'Acme Manufacturing') { acme = a; }
}
System.assert(acme != null, 'Acme Manufacturing not found. Re-run 01_load_core.apex.');

Map<String, Id> acmeContacts = new Map<String, Id>();
for (Contact c : [SELECT Id, LastName FROM Contact WHERE AccountId = :acme.Id]) {
    acmeContacts.put(c.LastName, c.Id);
}

List<Case> cases = new List<Case>();

// The one the demo is built around. Apex cannot backdate CreatedDate outside a
// test context, so the 12-day age lives in the subject and description instead.
Case acmeDefect = new Case(
    AccountId = acme.Id, ContactId = acmeContacts.get('Reyes'),
    Subject = 'Conveyor controller firmware defect halting Line 3 (open 12 days)',
    Status = sEscalated, Priority = 'High', Type = tProblem,
    Origin = oPhone, Reason = rBreak, IsEscalated = true,
    Description = 'Firmware release 4.2 causes intermittent controller faults on Line 3. Acme ' +
                  'has had two unplanned stoppages, the second costing most of a shift. ' +
                  'Escalated after the second incident. Engineering has a patch in QA with no ' +
                  'committed ship date. Originally reported 12 days ago. Plant manager Alan ' +
                  'Voss is the most affected and the least happy; CFO Teresa Nunez has asked ' +
                  'twice what we are doing about it.'
);
cases.add(acmeDefect);

cases.add(new Case(
    AccountId = acme.Id, ContactId = acmeContacts.get('Reyes'),
    Subject = 'Line 3 controller fault - first occurrence',
    Status = sClosed, Priority = 'Medium', Type = tProblem, Origin = oEmail, Reason = rBreak,
    Description = 'First Line 3 stoppage. Closed after a controller restart cleared it. ' +
                  'Root cause not identified at the time. In hindsight, the same firmware bug.'
));
cases.add(new Case(
    AccountId = acme.Id, ContactId = acmeContacts.get('Raman'),
    Subject = 'Invoice does not match the agreed renewal terms',
    Status = sClosed, Priority = 'Medium', Type = tQuestion, Origin = oEmail,
    Description = 'Billing discrepancy on the prior renewal. Resolved with a corrected invoice.'
));
cases.add(new Case(
    AccountId = acme.Id, ContactId = acmeContacts.get('Voss'),
    Subject = 'Request: shift-level reporting on line downtime',
    Status = sNew, Priority = 'Low', Type = tFeature, Origin = oWeb,
    Description = 'Alan wants downtime broken out by shift. Unrelated to the defect, but it ' +
                  'signals what he actually cares about.'
));

// ---------------------------------------------------------------------------
// 4. Filler cases across the rest of the org, so Acme is not the only account
//    with a support footprint. Roughly one in three accounts has a case.
// ---------------------------------------------------------------------------
List<String> subjects = new List<String>{
    'Dashboard loading slowly for the dispatch team',
    'SSO login loop for three user accounts',
    'Scheduled export failed overnight',
    'Request: add a column to the weekly report',
    'Mobile app crashes on the inspection form',
    'Duplicate records created by the nightly sync',
    'Permission set not granting expected access',
    'API rate limit reached during month-end',
    'Email alerts not reaching the shared inbox',
    'Question about data retention settings',
    'Attachment upload fails over 10MB',
    'Timezone wrong on scheduled reports'
};
List<String> fillerStatuses = new List<String>{ sClosed, sClosed, sWorking, sNew, sClosed, sWorking };
List<String> priorities = new List<String>{ 'Low', 'Medium', 'Medium', 'High' };

Integer seed = 761;
for (Integer i = 0; i < demoAccounts.size(); i++) {
    if (demoAccounts[i].Id == acme.Id) continue;
    seed = Math.mod(seed * 75 + 74, 65537);
    if (Math.mod(seed, 100) >= 33) continue;   // ~1 in 3 accounts

    Integer pick = Math.mod(seed / 7, subjects.size());
    cases.add(new Case(
        AccountId = demoAccounts[i].Id,
        Subject = subjects[pick],
        Status = fillerStatuses[Math.mod(seed / 11, fillerStatuses.size())],
        Priority = priorities[Math.mod(seed / 13, priorities.size())],
        Type = Math.mod(seed, 4) == 0 ? tFeature : tProblem,
        Origin = Math.mod(seed, 3) == 0 ? oPhone : (Math.mod(seed, 3) == 1 ? oEmail : oWeb)
    ));
}
insert cases;
System.debug('Inserted ' + cases.size() + ' cases.');

// ---------------------------------------------------------------------------
// 5. Case comments. These give the Acme briefing prompt something to read
//    beyond the case description — the back-and-forth, not just the summary.
// ---------------------------------------------------------------------------
List<CaseComment> comments = new List<CaseComment>{
    new CaseComment(
        ParentId = acmeDefect.Id, IsPublished = true,
        CommentBody = 'Day 1 - Marcus reports Line 3 faulting intermittently after the 4.2 ' +
                      'firmware update. Asked him to capture controller logs.'
    ),
    new CaseComment(
        ParentId = acmeDefect.Id, IsPublished = true,
        CommentBody = 'Day 3 - Logs confirm a timing fault in the 4.2 release. Reproduced in ' +
                      'the lab. Handed to engineering.'
    ),
    new CaseComment(
        ParentId = acmeDefect.Id, IsPublished = true,
        CommentBody = 'Day 6 - Second stoppage, roughly six hours of lost production. Alan ' +
                      'Voss escalated to his leadership. Case escalated on our side.'
    ),
    new CaseComment(
        ParentId = acmeDefect.Id, IsPublished = false,
        CommentBody = 'Internal - patch is in QA but there is no committed ship date. Renewal ' +
                      'is in flight and the new VP of Operations has not been briefed on any ' +
                      'of this. Needs an owner before the renewal conversation restarts.'
    ),
    new CaseComment(
        ParentId = acmeDefect.Id, IsPublished = true,
        CommentBody = 'Day 11 - Teresa Nunez (CFO) asked for a written update. Not yet sent.'
    )
};
insert comments;

System.debug('=====================================================');
System.debug('02 service load complete.');
System.debug('  Cases:         ' + cases.size());
System.debug('  Case comments: ' + comments.size());
System.debug('  Acme case history: 4 cases, 1 escalated');
System.debug('NEXT: run 03_load_marketing.apex');
System.debug('=====================================================');
