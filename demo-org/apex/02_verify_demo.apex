/* =============================================================================
 * Intro to Claude and Salesforce — verify the demo org
 * Run in: Developer Console -> Debug -> Open Execute Anonymous Window
 *         (check "Open Log", then read the USER_DEBUG lines)
 *
 * Run this AFTER 01_load_demo_data.apex, in a separate execution. It runs the
 * same shapes of query the live demo depends on, so if something is off you
 * find out now rather than on stage.
 *
 * Every check prints PASS or FAIL. All PASS means the slide 22 prompts have
 * data behind them.
 * ============================================================================= */

final String MARKER = 'DUG-DEMO-';
final String MARKER_LIKE = MARKER + '%';   // SOQL binds need a plain variable
Integer failures = 0;

System.debug('=====================================================');
System.debug('DUG demo org verification — ' + Date.today());
System.debug('=====================================================');

// ---------------------------------------------------------------------------
// Check 1: the data is actually there
// ---------------------------------------------------------------------------
Set<Id> demoAcctIds = new Map<Id, Account>(
    [SELECT Id FROM Account WHERE AccountNumber LIKE :MARKER_LIKE]
).keySet();

Integer acctCount = demoAcctIds.size();
Integer oppCount  = [SELECT COUNT() FROM Opportunity WHERE AccountId IN :demoAcctIds];
Integer caseCount = [SELECT COUNT() FROM Case WHERE AccountId IN :demoAcctIds];
// Task.AccountId is auto-populated from WhatId, so this stays scoped to the demo.
Integer taskCount = [SELECT COUNT() FROM Task WHERE Status = 'Completed' AND AccountId IN :demoAcctIds];

System.debug('Check 1 — record counts');
System.debug('  Demo accounts: ' + acctCount + ', opportunities: ' + oppCount +
             ', cases: ' + caseCount + ', completed activities on records: ' + taskCount);
if (acctCount >= 19 && oppCount >= 19) {
    System.debug('  PASS');
} else {
    failures++;
    System.debug('  FAIL — expected at least 19 accounts and 19 opportunities. Re-run the loader.');
}

// ---------------------------------------------------------------------------
// Check 2: slide 22, prompt 1 —
//   "Which of my opportunities closing this quarter have had no activity in
//    the last 14 days? Sort by amount."
//   Acme's $250K renewal must be at the top of this list.
// ---------------------------------------------------------------------------
System.debug('');
System.debug('Check 2 — "my quiet deals closing this quarter", sorted by amount');
List<Opportunity> atRisk = [
    SELECT Name, Amount, StageName, CloseDate, LastActivityDate
    FROM Opportunity
    WHERE OwnerId = :UserInfo.getUserId()
      AND IsClosed = false
      AND CloseDate = THIS_QUARTER
      AND (LastActivityDate < LAST_N_DAYS:14 OR LastActivityDate = null)
    ORDER BY Amount DESC
];
for (Opportunity o : atRisk) {
    System.debug('  $' + o.Amount.format() + '  ' + o.Name +
                 '  [' + o.StageName + ', closes ' + o.CloseDate +
                 ', last activity ' + o.LastActivityDate + ']');
}
if (atRisk.isEmpty()) {
    failures++;
    System.debug('  FAIL — no quiet deals came back. Either the LastActivityDate rollup has not ' +
                 'landed yet (wait a moment and re-run), or your org uses a custom fiscal year ' +
                 'so THIS_QUARTER does not match the calendar quarter the loader used.');
} else if (!atRisk[0].Name.startsWith('Acme Manufacturing')) {
    failures++;
    System.debug('  FAIL — expected Acme Manufacturing at the top, got "' + atRisk[0].Name +
                 '". Check that nothing else was created above $250K with stale activity.');
} else {
    System.debug('  PASS — Acme leads with ' + atRisk.size() + ' quiet deal(s) in the list.');
}

// ---------------------------------------------------------------------------
// Check 3: slide 22, prompt 2 — the Acme briefing.
//   Claude needs to be able to connect the escalated case to the quiet renewal
//   and spot the new VP of Operations. All three have to exist on one account.
// ---------------------------------------------------------------------------
System.debug('');
System.debug('Check 3 — Acme briefing ingredients');
List<Account> acmeList = [
    SELECT Id, Name, Industry,
           (SELECT Name, Title FROM Contacts ORDER BY LastName),
           (SELECT Name, Amount, StageName, CloseDate, LastActivityDate FROM Opportunities),
           (SELECT CaseNumber, Subject, Status, Priority, IsEscalated FROM Cases)
    FROM Account
    WHERE Name = 'Acme Manufacturing' AND AccountNumber LIKE :MARKER_LIKE
];
if (acmeList.isEmpty()) {
    failures++;
    System.debug('  FAIL — no Acme Manufacturing account found.');
} else {
    Account a = acmeList[0];
    Boolean hasVpOps = false;
    for (Contact c : a.Contacts) {
        System.debug('  Contact: ' + c.Name + ' — ' + c.Title);
        if (c.Title != null && c.Title.containsIgnoreCase('VP of Operations')) hasVpOps = true;
    }
    Boolean hasRenewal = false;
    for (Opportunity o : a.Opportunities) {
        System.debug('  Opp: ' + o.Name + ' $' + o.Amount.format() + ' — ' + o.StageName +
                     ', last activity ' + o.LastActivityDate);
        if (o.Amount == 250000) hasRenewal = true;
    }
    Boolean hasEscalated = false;
    for (Case c : a.Cases) {
        System.debug('  Case: ' + c.CaseNumber + ' ' + c.Subject +
                     ' — ' + c.Status + '/' + c.Priority + ', escalated=' + c.IsEscalated);
        if (c.IsEscalated || c.Status == 'Escalated') hasEscalated = true;
    }
    if (hasVpOps && hasRenewal && hasEscalated) {
        System.debug('  PASS — VP of Operations, $250K renewal and escalated case all present.');
    } else {
        failures++;
        System.debug('  FAIL — missing: ' +
            (hasVpOps ? '' : 'VP of Operations contact; ') +
            (hasRenewal ? '' : '$250K renewal; ') +
            (hasEscalated ? '' : 'escalated case; '));
    }
}

// ---------------------------------------------------------------------------
// Check 4: Acme really is quiet. The story says three weeks.
// ---------------------------------------------------------------------------
System.debug('');
System.debug('Check 4 — Acme has been quiet long enough');
List<Opportunity> acmeOpps = [
    SELECT Name, LastActivityDate FROM Opportunity
    WHERE Account.Name = 'Acme Manufacturing' AND Amount = 250000
    LIMIT 1
];
if (acmeOpps.isEmpty() || acmeOpps[0].LastActivityDate == null) {
    failures++;
    System.debug('  FAIL — no LastActivityDate on the Acme renewal. The rollup only counts ' +
                 'COMPLETED tasks; confirm the loader inserted them with Status = Completed.');
} else {
    Integer quietDays = acmeOpps[0].LastActivityDate.daysBetween(Date.today());
    System.debug('  Last activity was ' + quietDays + ' days ago (' + acmeOpps[0].LastActivityDate + ')');
    if (quietDays >= 21) {
        System.debug('  PASS');
    } else {
        failures++;
        System.debug('  FAIL — the story on slide 21 says "no activity in 3 weeks". ' +
                     'Re-run the loader so the dates are relative to today.');
    }
}

// ---------------------------------------------------------------------------
// Check 5: slide 22, prompt 4 — the dashboard.
//   Needs several stages and more than one owner to be worth charting.
// ---------------------------------------------------------------------------
System.debug('');
System.debug('Check 5 — dashboard has something to chart');
Set<String> stagesInPlay = new Set<String>();
Set<Id> ownersInPlay = new Set<Id>();
for (Opportunity o : [
    SELECT StageName, OwnerId FROM Opportunity
    WHERE IsClosed = false AND CloseDate = THIS_QUARTER
      AND Account.AccountNumber LIKE :MARKER_LIKE
]) {
    stagesInPlay.add(o.StageName);
    ownersInPlay.add(o.OwnerId);
}
System.debug('  Open deals this quarter span ' + stagesInPlay.size() + ' stage(s) across ' +
             ownersInPlay.size() + ' owner(s).');
System.debug('  Stages: ' + stagesInPlay);
if (stagesInPlay.size() >= 3) {
    System.debug('  PASS on stage spread.');
} else {
    failures++;
    System.debug('  FAIL — pipeline-by-stage will look thin with fewer than 3 stages.');
}
if (ownersInPlay.size() < 2) {
    System.debug('  NOTE — only one owner, so "filter by owner" will be a no-op. ' +
                 'Not fatal; create a couple of extra users and re-run the loader if you want it.');
}

// ---------------------------------------------------------------------------
// Result
// ---------------------------------------------------------------------------
System.debug('');
System.debug('=====================================================');
if (failures == 0) {
    System.debug('ALL CHECKS PASSED — the org is ready for the demo.');
} else {
    System.debug(failures + ' CHECK(S) FAILED — see the FAIL lines above.');
}
System.debug('=====================================================');
