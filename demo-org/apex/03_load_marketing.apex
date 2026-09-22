/* =============================================================================
 * DUG demo org — 03: marketing records
 * Leads, campaigns and campaign members. Run AFTER 01_load_core.apex.
 *
 * Tagging, so cleanup can find these again without guessing:
 *   - every demo lead has an @dug-demo.example email address
 *   - every demo campaign is a child of one parent campaign, "DUG Demo Data"
 * Neither object hangs off Account, so neither is caught by the cascade delete
 * that removes everything else.
 * ============================================================================= */

Organization thisOrg = [SELECT Id, Name, IsSandbox, OrganizationType FROM Organization LIMIT 1];
System.assert(
    thisOrg.IsSandbox || thisOrg.OrganizationType == 'Developer Edition',
    'REFUSING TO RUN. Not a Developer Edition org or sandbox: "' + thisOrg.Name + '".'
);

final String LEAD_DOMAIN = '@dug-demo.example';
final String LEAD_LIKE = '%' + LEAD_DOMAIN;
final String PARENT_CAMPAIGN = 'DUG Demo Data';
Date today = Date.today();

// ---------------------------------------------------------------------------
// 1. Wipe any previous 03 run
// ---------------------------------------------------------------------------
List<Lead> priorLeads = [SELECT Id FROM Lead WHERE Email LIKE :LEAD_LIKE];
if (!priorLeads.isEmpty()) {
    delete priorLeads;
    Database.emptyRecycleBin(priorLeads);
    System.debug('Removed ' + priorLeads.size() + ' lead(s) from a previous run.');
}
// Children first, then the parent — a campaign with children cannot be deleted.
List<Campaign> priorChildren = [
    SELECT Id FROM Campaign WHERE Parent.Name = :PARENT_CAMPAIGN
];
if (!priorChildren.isEmpty()) {
    delete priorChildren;   // cascades to their campaign members
}
List<Campaign> priorParent = [SELECT Id FROM Campaign WHERE Name = :PARENT_CAMPAIGN];
if (!priorParent.isEmpty()) {
    delete priorParent;
    Database.emptyRecycleBin(priorParent);
}

// ---------------------------------------------------------------------------
// 2. Picklist safety
// ---------------------------------------------------------------------------
Set<String> validLeadStatus = new Set<String>();
for (Schema.PicklistEntry pe : Lead.Status.getDescribe().getPicklistValues()) {
    if (pe.isActive()) validLeadStatus.add(pe.getValue());
}
Set<String> validLeadSource = new Set<String>();
for (Schema.PicklistEntry pe : Lead.LeadSource.getDescribe().getPicklistValues()) {
    if (pe.isActive()) validLeadSource.add(pe.getValue());
}
Set<String> validIndustries = new Set<String>();
for (Schema.PicklistEntry pe : Lead.Industry.getDescribe().getPicklistValues()) {
    if (pe.isActive()) validIndustries.add(pe.getValue());
}
Set<String> validCampaignTypes = new Set<String>();
for (Schema.PicklistEntry pe : Campaign.Type.getDescribe().getPicklistValues()) {
    if (pe.isActive()) validCampaignTypes.add(pe.getValue());
}

// Lead.Status is required and its default values vary, so pick carefully.
List<String> leadStatuses = new List<String>();
for (String s : new List<String>{'Open - Not Contacted', 'Working - Contacted', 'Open', 'Contacted'}) {
    if (validLeadStatus.contains(s)) leadStatuses.add(s);
}
if (leadStatuses.isEmpty()) leadStatuses.add(new List<String>(validLeadStatus)[0]);

List<String> leadSources = new List<String>();
for (String s : new List<String>{'Web', 'Phone Inquiry', 'Partner Referral', 'Trade Show', 'Other'}) {
    if (validLeadSource.contains(s)) leadSources.add(s);
}
if (leadSources.isEmpty()) leadSources.add(null);

// ---------------------------------------------------------------------------
// 3. Campaigns, under a single parent so cleanup can find them
// ---------------------------------------------------------------------------
Campaign parent = new Campaign(
    Name = PARENT_CAMPAIGN, IsActive = false,
    Description = 'Container for DUG demo campaigns. Delete this and its children to remove ' +
                  'the demo marketing data.'
);
insert parent;

List<String> campaignSpecs = new List<String>{
    'FY26 Manufacturing Webinar Series|Webinar|-120|45000',
    'Field Service Buyers Guide|Other|-75|12000',
    'Midwest Trade Show - Spring|Conference|-200|80000',
    'Quarterly Customer Newsletter|Email|-30|3000',
    'Renewal Nurture - At Risk Accounts|Email|-21|8000',
    'Partner Co-Marketing - Integrators|Partners|-150|25000'
};
List<Campaign> campaigns = new List<Campaign>();
for (String spec : campaignSpecs) {
    List<String> f = spec.split('\\|');
    campaigns.add(new Campaign(
        Name = f[0],
        ParentId = parent.Id,
        Type = validCampaignTypes.contains(f[1]) ? f[1] : null,
        IsActive = true,
        StartDate = today.addDays(Integer.valueOf(f[2])),
        EndDate = today.addDays(Integer.valueOf(f[2]) + 60),
        BudgetedCost = Decimal.valueOf(f[3]),
        ActualCost = Decimal.valueOf(f[3]) * 0.9,
        Description = 'Fictional campaign for the DUG demo org.'
    ));
}
insert campaigns;

// ---------------------------------------------------------------------------
// 4. Leads
// ---------------------------------------------------------------------------
List<String> firstNames = new List<String>{
    'Rowan', 'Imani', 'Casper', 'Delia', 'Emmett', 'Farrah', 'Gideon', 'Halle',
    'Ivo', 'Juno', 'Kai', 'Lena', 'Mateo', 'Nell', 'Otto', 'Perla',
    'Quinn', 'Rafe', 'Sana', 'Tobias', 'Ursula', 'Vidal', 'Wren', 'Xiomara'
};
List<String> lastNames = new List<String>{
    'Abernathy', 'Baptiste', 'Cortez', 'Duval', 'Eklund', 'Fiore', 'Greaves',
    'Hirsch', 'Ibarra', 'Jovanovic', 'Kraus', 'Lachlan', 'Marek', 'Nkemelu',
    'Ostrowski', 'Pankhurst', 'Quintero', 'Rask', 'Strand', 'Tveit'
};
List<String> companySpecs = new List<String>{
    'Cobalt Tool Works|Manufacturing', 'Ridgeway Transit|Transportation',
    'Alder Health Network|Healthcare', 'Pinebrook Energy|Energy',
    'Marlow Assurance|Insurance', 'Hollis Provisions|Food & Beverage',
    'Sturgis Builders|Construction', 'Tiller Bank Group|Banking',
    'Fernhill Growers|Agriculture', 'Bracken Academy|Education',
    'Vernon Street Retail|Retail', 'Helix Labs|Biotechnology',
    'Wayfarer Hotels|Hospitality', 'Quarrystone Materials|Energy',
    'Lantern Media|Media', 'Sentinel Networks|Technology',
    'Birchwood Care|Healthcare', 'Foundry Components|Manufacturing',
    'Crosswind Freight|Transportation', 'Beacon Analytics|Technology'
};
List<String> leadTitles = new List<String>{
    'Operations Manager', 'IT Director', 'Salesforce Administrator',
    'VP Operations', 'Business Analyst', 'Head of Service', 'CFO',
    'Continuous Improvement Lead'
};

List<Lead> leads = new List<Lead>();
Integer seed = 4093;
for (Integer i = 0; i < 150; i++) {
    seed = Math.mod(seed * 75 + 74, 65537);
    List<String> co = companySpecs[Math.mod(seed, companySpecs.size())].split('\\|');
    String fn = firstNames[Math.mod(seed / 3, firstNames.size())];
    String ln = lastNames[Math.mod(seed / 7, lastNames.size())];

    leads.add(new Lead(
        FirstName = fn, LastName = ln,
        Company = co[0],
        Title = leadTitles[Math.mod(seed / 11, leadTitles.size())],
        Industry = validIndustries.contains(co[1]) ? co[1] : null,
        Email = fn.toLowerCase() + '.' + ln.toLowerCase() + i + LEAD_DOMAIN,
        Phone = '(555) 01' + String.valueOf(Math.mod(seed, 90) + 10).leftPad(2, '0') +
                String.valueOf(i).leftPad(2, '0'),
        Status = leadStatuses[Math.mod(seed / 13, leadStatuses.size())],
        LeadSource = leadSources[Math.mod(seed / 17, leadSources.size())],
        NumberOfEmployees = 20 + Math.mod(seed, 2500),
        Description = 'Fictional demo lead for the DUG session.'
    ));
}
insert leads;
System.debug('Inserted ' + leads.size() + ' leads.');

// ---------------------------------------------------------------------------
// 5. Campaign members. Leads and demo contacts both get attributed, so
//    "which campaigns touched this account?" has an answer.
//    'Sent' and 'Responded' are the default member statuses on a new campaign.
// ---------------------------------------------------------------------------
List<Contact> demoContacts = [
    SELECT Id FROM Contact
    WHERE Account.AccountNumber LIKE 'DUG-DEMO-%'
    ORDER BY CreatedDate
    LIMIT 200
];

List<CampaignMember> members = new List<CampaignMember>();
seed = 8675;
for (Integer i = 0; i < leads.size(); i++) {
    seed = Math.mod(seed * 75 + 74, 65537);
    if (Math.mod(seed, 100) >= 70) continue;   // ~70% of leads came from a campaign
    members.add(new CampaignMember(
        CampaignId = campaigns[Math.mod(seed / 3, campaigns.size())].Id,
        LeadId = leads[i].Id,
        Status = Math.mod(seed, 3) == 0 ? 'Responded' : 'Sent'
    ));
}
for (Integer i = 0; i < demoContacts.size(); i++) {
    seed = Math.mod(seed * 75 + 74, 65537);
    if (Math.mod(seed, 100) >= 45) continue;   // ~45% of contacts are campaign members
    members.add(new CampaignMember(
        CampaignId = campaigns[Math.mod(seed / 5, campaigns.size())].Id,
        ContactId = demoContacts[i].Id,
        Status = Math.mod(seed, 4) == 0 ? 'Responded' : 'Sent'
    ));
}
// A duplicate member on the same campaign is rejected, so let partial success
// through rather than losing the whole batch to one collision.
Database.insert(members, false);

Integer memberCount = [SELECT COUNT() FROM CampaignMember WHERE Campaign.Parent.Name = :PARENT_CAMPAIGN];

System.debug('=====================================================');
System.debug('03 marketing load complete.');
System.debug('  Campaigns:        ' + campaigns.size() + ' (+1 parent container)');
System.debug('  Leads:            ' + leads.size());
System.debug('  Campaign members: ' + memberCount);
System.debug('NEXT: run 04_load_products.apex');
System.debug('=====================================================');
