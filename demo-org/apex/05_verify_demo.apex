/* =============================================================================
 * DUG demo org — 05: verification
 * Run LAST, as its own execution, with "Open Log" checked.
 *
 * Runs the same shapes of query the live demo depends on and prints PASS or
 * FAIL for each. Its job is to find problems here rather than on stage.
 *
 * This has to be a separate execution from 01: LastActivityDate is a platform
 * rollup computed after the loading transaction commits, so querying it inside
 * that transaction returns null and every staleness check would fail.
 * ============================================================================= */

final String MARKER_LIKE = 'DUG-DEMO-%';
final String LEAD_LIKE = '%@dug-demo.example';
Integer failures = 0;
Integer warnings = 0;
Date today = Date.today();

System.debug('=====================================================');
System.debug('DUG demo org verification — ' + today);
System.debug('=====================================================');

// ---------------------------------------------------------------------------
// Check 1 — everything got loaded
// ---------------------------------------------------------------------------
Set<Id> demoAcctIds = new Map<Id, Account>(
    [SELECT Id FROM Account WHERE AccountNumber LIKE :MARKER_LIKE]
).keySet();

Integer nAcct  = demoAcctIds.size();
Integer nCon   = [SELECT COUNT() FROM Contact WHERE AccountId IN :demoAcctIds];
Integer nOpp   = [SELECT COUNT() FROM Opportunity WHERE AccountId IN :demoAcctIds];
Integer nCase  = [SELECT COUNT() FROM Case WHERE AccountId IN :demoAcctIds];
Integer nTask  = [SELECT COUNT() FROM Task WHERE AccountId IN :demoAcctIds AND Status = 'Completed'];
Integer nEvent = [SELECT COUNT() FROM Event WHERE AccountId IN :demoAcctIds];
Integer nLead  = [SELECT COUNT() FROM Lead WHERE Email LIKE :LEAD_LIKE];
Integer nCamp  = [SELECT COUNT() FROM Campaign WHERE Parent.Name = 'DUG Demo Data'];
Integer nCM    = [SELECT COUNT() FROM CampaignMember WHERE Campaign.Parent.Name = 'DUG Demo Data'];
Integer nOLI   = [SELECT COUNT() FROM OpportunityLineItem WHERE Opportunity.AccountId IN :demoAcctIds];
Integer nCC    = [SELECT COUNT() FROM CaseComment WHERE Parent.AccountId IN :demoAcctIds];

System.debug('Check 1 — record counts');
System.debug('  Accounts ' + nAcct + ' | Contacts ' + nCon + ' | Opportunities ' + nOpp);
System.debug('  Cases ' + nCase + ' | Case comments ' + nCC + ' | Tasks ' + nTask +
             ' | Events ' + nEvent);
System.debug('  Leads ' + nLead + ' | Campaigns ' + nCamp + ' | Campaign members ' + nCM);
System.debug('  Opportunity line items ' + nOLI);
System.debug('  TOTAL ' + (nAcct + nCon + nOpp + nCase + nCC + nTask + nEvent +
                           nLead + nCamp + nCM + nOLI));

if (nAcct >= 240 && nOpp >= 300) {
    System.debug('  PASS — script 01 loaded.');
} else {
    failures++;
    System.debug('  FAIL — expected ~250 accounts and ~360 opportunities. Re-run 01_load_core.apex.');
}
if (nCase < 50)  { warnings++; System.debug('  WARN — few cases. Did 02_load_service.apex run?'); }
if (nLead < 100) { warnings++; System.debug('  WARN — few leads. Did 03_load_marketing.apex run?'); }
if (nOLI < 100)  { warnings++; System.debug('  WARN — few line items. Did 04_load_products.apex run?'); }

// ---------------------------------------------------------------------------
// Check 2 — the first demo prompt:
//   "Which of my opportunities closing this quarter have had no activity in the
//    last 14 days? Sort by amount."
//   Acme's $250K renewal has to come back on top.
// ---------------------------------------------------------------------------
System.debug('');
System.debug('Check 2 — my quiet deals closing this quarter, by amount');
List<Opportunity> atRisk = [
    SELECT Name, Amount, StageName, CloseDate, LastActivityDate
    FROM Opportunity
    WHERE OwnerId = :UserInfo.getUserId()
      AND IsClosed = false
      AND CloseDate = THIS_QUARTER
      AND (LastActivityDate < LAST_N_DAYS:14 OR LastActivityDate = null)
    ORDER BY Amount DESC
];
System.debug('  ' + atRisk.size() + ' quiet deal(s). Top 8:');
for (Integer i = 0; i < Math.min(8, atRisk.size()); i++) {
    Opportunity o = atRisk[i];
    System.debug('   ' + (i + 1) + '. $' + o.Amount.format() + '  ' + o.Name +
                 '  [' + o.StageName + ', closes ' + o.CloseDate +
                 ', last activity ' + o.LastActivityDate + ']');
}
if (atRisk.isEmpty()) {
    failures++;
    System.debug('  FAIL — nothing came back. Either the LastActivityDate rollup has not landed ' +
                 'yet (give it a moment and re-run), or your org uses a custom fiscal year so ' +
                 'THIS_QUARTER does not line up with the calendar quarter the loader used.');
} else if (!atRisk[0].Name.startsWith('Acme Manufacturing')) {
    failures++;
    System.debug('  FAIL — expected Acme on top, got "' + atRisk[0].Name + '" at $' +
                 atRisk[0].Amount.format() + '. Something was created above $250K with stale ' +
                 'activity; check the amount clamp in 01_load_core.apex.');
} else {
    System.debug('  PASS — Acme leads ' + atRisk.size() + ' quiet deals.');
}

// ---------------------------------------------------------------------------
// Check 3 — the filter has to visibly do work. There should be a LARGER deal
//   closing this quarter that is NOT quiet, so the answer is not simply
//   "the biggest deal in the pipeline".
// ---------------------------------------------------------------------------
System.debug('');
System.debug('Check 3 — the 14-day filter changes the answer');
List<Opportunity> biggestOpen = [
    SELECT Name, Amount, LastActivityDate FROM Opportunity
    WHERE IsClosed = false AND CloseDate = THIS_QUARTER AND AccountId IN :demoAcctIds
    ORDER BY Amount DESC LIMIT 1
];
if (!biggestOpen.isEmpty()) {
    System.debug('  Largest open deal this quarter: $' + biggestOpen[0].Amount.format() +
                 '  ' + biggestOpen[0].Name + '  (last activity ' +
                 biggestOpen[0].LastActivityDate + ')');
    if (biggestOpen[0].Name.startsWith('Acme Manufacturing')) {
        warnings++;
        System.debug('  WARN — Acme is also the biggest deal overall, so the filter looks like ' +
                     'it did nothing. Not broken, just a weaker demo moment.');
    } else {
        System.debug('  PASS — a bigger deal sits above Acme unfiltered, so the filter earns its keep.');
    }
}

// ---------------------------------------------------------------------------
// Check 4 — the Acme briefing prompt. Everything Claude needs to connect the
//   escalated case to the quiet renewal and the unbriefed new VP.
// ---------------------------------------------------------------------------
System.debug('');
System.debug('Check 4 — Acme briefing ingredients');
List<Account> acmeList = [
    SELECT Id, Name, Industry,
           (SELECT Name, Title FROM Contacts ORDER BY LastName),
           (SELECT Name, Amount, StageName, CloseDate, IsClosed, LastActivityDate
              FROM Opportunities ORDER BY CloseDate DESC),
           (SELECT CaseNumber, Subject, Status, Priority, IsEscalated FROM Cases)
    FROM Account
    WHERE Name = 'Acme Manufacturing' AND AccountNumber LIKE :MARKER_LIKE
];
if (acmeList.isEmpty()) {
    failures++;
    System.debug('  FAIL — no Acme Manufacturing account. Re-run 01_load_core.apex.');
} else {
    Account a = acmeList[0];
    Boolean hasVpOps = false, hasRenewal = false, hasEscalated = false;
    Integer closedHistory = 0;

    for (Contact c : a.Contacts) {
        if (c.Title != null && c.Title.containsIgnoreCase('VP of Operations')) hasVpOps = true;
    }
    for (Opportunity o : a.Opportunities) {
        if (o.Amount == 250000 && !o.IsClosed) hasRenewal = true;
        if (o.IsClosed) closedHistory++;
    }
    for (Case c : a.Cases) {
        if (c.IsEscalated || c.Status == 'Escalated') hasEscalated = true;
    }
    Integer acmeComments = [SELECT COUNT() FROM CaseComment WHERE Parent.AccountId = :a.Id];

    System.debug('  Contacts ' + a.Contacts.size() + ' | Opportunities ' + a.Opportunities.size() +
                 ' (' + closedHistory + ' closed) | Cases ' + a.Cases.size() +
                 ' | Case comments ' + acmeComments);
    if (hasVpOps && hasRenewal && hasEscalated) {
        System.debug('  PASS — VP of Operations, open $250K renewal and escalated case all present.');
    } else {
        failures++;
        System.debug('  FAIL — missing: ' +
            (hasVpOps ? '' : 'VP of Operations contact; ') +
            (hasRenewal ? '' : 'open $250K renewal; ') +
            (hasEscalated ? '' : 'escalated case; '));
    }
    if (acmeComments < 3) {
        warnings++;
        System.debug('  WARN — few case comments, so the briefing has less to synthesise. ' +
                     'Did 02_load_service.apex run?');
    }
}

// ---------------------------------------------------------------------------
// Check 5 — Acme really has been quiet. Slide 21 says three weeks.
// ---------------------------------------------------------------------------
System.debug('');
System.debug('Check 5 — Acme has been quiet long enough');
List<Opportunity> acmeRenewal = [
    SELECT Name, LastActivityDate FROM Opportunity
    WHERE Account.Name = 'Acme Manufacturing' AND Amount = 250000 AND IsClosed = false
    LIMIT 1
];
if (acmeRenewal.isEmpty() || acmeRenewal[0].LastActivityDate == null) {
    failures++;
    System.debug('  FAIL — no LastActivityDate on the Acme renewal. The rollup only counts ' +
                 'COMPLETED tasks; check that 01 inserted them with Status = Completed.');
} else {
    Integer quietDays = acmeRenewal[0].LastActivityDate.daysBetween(today);
    System.debug('  Last activity ' + quietDays + ' days ago (' +
                 acmeRenewal[0].LastActivityDate + ')');
    if (quietDays >= 21) {
        System.debug('  PASS');
    } else {
        failures++;
        System.debug('  FAIL — slide 21 says "no activity in 3 weeks". Re-run 01 so the dates ' +
                     'are relative to today.');
    }
}

// ---------------------------------------------------------------------------
// Check 6 — the dashboard prompt needs stages and owners worth charting
// ---------------------------------------------------------------------------
System.debug('');
System.debug('Check 6 — dashboard has something to chart');
Set<String> stagesInPlay = new Set<String>();
Set<Id> ownersInPlay = new Set<Id>();
Integer openThisQuarter = 0;
for (Opportunity o : [
    SELECT StageName, OwnerId FROM Opportunity
    WHERE IsClosed = false AND CloseDate = THIS_QUARTER AND AccountId IN :demoAcctIds
]) {
    stagesInPlay.add(o.StageName);
    ownersInPlay.add(o.OwnerId);
    openThisQuarter++;
}
System.debug('  ' + openThisQuarter + ' open deals this quarter across ' + stagesInPlay.size() +
             ' stage(s) and ' + ownersInPlay.size() + ' owner(s).');
if (stagesInPlay.size() >= 3) {
    System.debug('  PASS on stage spread.');
} else {
    failures++;
    System.debug('  FAIL — pipeline-by-stage looks thin below 3 stages.');
}
if (ownersInPlay.size() < 2) {
    warnings++;
    System.debug('  WARN — one owner only, so "filter by owner" is a no-op. Create a few extra ' +
                 'users and re-run 01 if you want that part of the demo to land.');
}

// ---------------------------------------------------------------------------
// Check 7 — opportunity amounts survived script 04. Line items override Amount,
//   so this is where that would show up.
// ---------------------------------------------------------------------------
System.debug('');
System.debug('Check 7 — amounts intact after products were added');
if (nOLI == 0) {
    System.debug('  SKIP — no line items, so nothing could have overridden an amount.');
} else {
    List<Opportunity> mismatched = [
        SELECT Id, Name, Amount FROM Opportunity
        WHERE AccountId IN :demoAcctIds AND HasOpportunityLineItem = true AND Amount = null
        LIMIT 5
    ];
    Integer acmeStillRight = [
        SELECT COUNT() FROM Opportunity
        WHERE Account.Name = 'Acme Manufacturing' AND IsClosed = false AND Amount = 250000
    ];
    if (acmeStillRight > 0 && mismatched.isEmpty()) {
        System.debug('  PASS — Acme is still exactly $250,000 and no priced deal lost its amount.');
    } else {
        failures++;
        System.debug('  FAIL — amounts drifted when line items were added. Re-run ' +
                     '04_load_products.apex, or delete the demo line items and skip script 04.');
    }
}

// ---------------------------------------------------------------------------
// Check 8 — historical data, for trend and win-rate questions
// ---------------------------------------------------------------------------
System.debug('');
System.debug('Check 8 — closed history for trend questions');
Integer won = [SELECT COUNT() FROM Opportunity WHERE AccountId IN :demoAcctIds AND IsWon = true];
Integer lost = [
    SELECT COUNT() FROM Opportunity
    WHERE AccountId IN :demoAcctIds AND IsClosed = true AND IsWon = false
];
Integer oldestDays = 0;
List<Opportunity> oldest = [
    SELECT CloseDate FROM Opportunity
    WHERE AccountId IN :demoAcctIds AND IsClosed = true
    ORDER BY CloseDate ASC LIMIT 1
];
if (!oldest.isEmpty()) oldestDays = oldest[0].CloseDate.daysBetween(today);
System.debug('  Won ' + won + ' | Lost ' + lost + ' | history reaches back ' +
             oldestDays + ' days');
if (won + lost >= 100 && oldestDays > 365) {
    Integer rate = (won * 100) / Math.max(won + lost, 1);
    System.debug('  PASS — ' + rate + '% win rate over more than a year of history.');
} else {
    warnings++;
    System.debug('  WARN — thin closed history, so quarter-over-quarter questions will be dull.');
}

// ---------------------------------------------------------------------------
// Result
// ---------------------------------------------------------------------------
System.debug('');
System.debug('=====================================================');
if (failures == 0 && warnings == 0) {
    System.debug('ALL CHECKS PASSED — the org is ready.');
} else if (failures == 0) {
    System.debug('PASSED with ' + warnings + ' warning(s) — usable, see the WARN lines.');
} else {
    System.debug(failures + ' CHECK(S) FAILED and ' + warnings + ' warning(s). See above.');
}
System.debug('=====================================================');
