public class CreationOfFeeSchedule {
 public static void createFeeScheduleAndOppService(List<Opportunity> oppList) {
    if (oppList == null || oppList.isEmpty()) {
        System.debug('No opportunities to process.');
        return;
    }

    // Fetch Opportunity fields dynamically
    Map<String, Schema.SObjectField> opportunityFields = Schema.SObjectType.Opportunity.fields.getMap();

    // Determine checked Opportunity field labels
    Set<String> checkedFieldLabels = new Set<String>();
    for (Opportunity opp : oppList) {
        for (String fieldName : opportunityFields.keySet()) {
            Schema.SObjectField field = opportunityFields.get(fieldName);
            Schema.DescribeFieldResult fieldDescribe = field.getDescribe();

            if (fieldDescribe.getType() == Schema.DisplayType.Boolean && opp.get(fieldName) == true) {
                checkedFieldLabels.add(fieldDescribe.getLabel());
            }
        }
    }

    System.debug('Checked Opportunity field labels: ' + checkedFieldLabels);

    // Query metadata matching checked field labels
    List<Project__mdt> projectMdtList = [
        SELECT Label, Column_Names__c, Service_Type__c
        FROM Project__mdt
        WHERE Label IN :checkedFieldLabels
    ];

    Map<String, String> columnNamesMap = new Map<String, String>();
    Map<String, String> serviceTypeMap = new Map<String, String>();

    for (Project__mdt metadata : projectMdtList) {
        columnNamesMap.put(metadata.Label, metadata.Column_Names__c);
        serviceTypeMap.put(metadata.Label, metadata.Service_Type__c);
    }

    // Prepare collections for bulk processing
    List<Fee_Schedule__c> feeScheduleList = new List<Fee_Schedule__c>();
    List<OpportunityService__c> oppServiceList = new List<OpportunityService__c>();
    List<FeeScheduleOpportunityService__c> feeScheduleOppServiceList = new List<FeeScheduleOpportunityService__c>();

    // Query existing Opportunity Services to avoid duplicates
    Set<Id> oppIds = new Set<Id>();
    for (Opportunity opp : oppList) {
        oppIds.add(opp.Id);
    }

    Map<Id, Set<String>> existingOppServicesMap = new Map<Id, Set<String>>();
    for (OpportunityService__c oppService : [
        SELECT Opportunity__c, Name
        FROM OpportunityService__c
        WHERE Opportunity__c IN :oppIds
    ]) {
        if (!existingOppServicesMap.containsKey(oppService.Opportunity__c)) {
            existingOppServicesMap.put(oppService.Opportunity__c, new Set<String>());
        }
        existingOppServicesMap.get(oppService.Opportunity__c).add(oppService.Name);
    }

    // Query existing Fee Schedules to avoid duplicates
    Map<Id, Set<Date>> existingFeeSchedulesMap = new Map<Id, Set<Date>>();
    for (Fee_Schedule__c fee : [
        SELECT Opportunity__c, Billing_Date__c
        FROM Fee_Schedule__c
        WHERE Opportunity__c IN :oppIds
    ]) {
        if (!existingFeeSchedulesMap.containsKey(fee.Opportunity__c)) {
            existingFeeSchedulesMap.put(fee.Opportunity__c, new Set<Date>());
        }
        existingFeeSchedulesMap.get(fee.Opportunity__c).add(fee.Billing_Date__c);
    }

    // Process Opportunities
    for (Opportunity opp : oppList) {
        Date startDate = opp.Start_Dates__c;
        Date endDate = opp.End_Date__c;

        if (startDate == null || endDate == null) {
            System.debug('Start Date or End Date is missing for Opportunity: ' + opp.Id);
            continue;
        }

        Set<Date> existingBillingDates = existingFeeSchedulesMap.containsKey(opp.Id) ? existingFeeSchedulesMap.get(opp.Id) : new Set<Date>();
        Set<String> existingServices = existingOppServicesMap.containsKey(opp.Id) ? existingOppServicesMap.get(opp.Id) : new Set<String>();

        for (String fieldLabel : checkedFieldLabels) {
            if (columnNamesMap.containsKey(fieldLabel)) {
                String columnNames = columnNamesMap.get(fieldLabel);
                List<String> columns = columnNames != null ? columnNames.split(',') : new List<String>();
                String serviceType = serviceTypeMap.get(fieldLabel);

                if (columns.isEmpty()) {
                    continue; // Skip if no columns are defined
                }

                // Create Fee Schedules for additional months only
                Date currentMonth = startDate;
                while (currentMonth <= endDate) {
                    if (!existingBillingDates.contains(currentMonth)) {
                        Fee_Schedule__c feeSchedule = new Fee_Schedule__c();
                        feeSchedule.Opportunity__c = opp.Id;
                        feeSchedule.Billing_Date__c = currentMonth;
                        feeSchedule.Name = currentMonth + '' + fieldLabel;
                        feeSchedule.Project_Type__c = serviceType;
                        feeScheduleList.add(feeSchedule);
                    }
                    currentMonth = currentMonth.addMonths(1);
                }

                // Create Opportunity Services if not already present
                for (String columnName : columns) {
                    if (!existingServices.contains(columnName.trim())) {
                        OpportunityService__c oppService = new OpportunityService__c();
                        oppService.Opportunity__c = opp.Id;
                        oppService.Name = columnName.trim();
                        oppService.Service_Name__c = fieldLabel;
                        oppService.Project_Type__c = serviceType;
                        oppServiceList.add(oppService);
                    }
                }
            }
        }
    }

    // Bulk insert Fee Schedules
    if (!feeScheduleList.isEmpty()) {
        insert feeScheduleList;
        System.debug('Inserted Fee Schedules: ' + feeScheduleList.size());
    }

    // Bulk insert Opportunity Services
    if (!oppServiceList.isEmpty()) {
        insert oppServiceList;
        System.debug('Inserted Opportunity Services: ' + oppServiceList.size());
    }

    // Create FeeScheduleOpportunityService relationships
    if (!feeScheduleList.isEmpty() && !oppServiceList.isEmpty()) {
        for (Fee_Schedule__c feeSchedule : feeScheduleList) {
            for (OpportunityService__c oppService : oppServiceList) {
                FeeScheduleOpportunityService__c feeScheduleOppService = new FeeScheduleOpportunityService__c();
                feeScheduleOppService.Fee_Schedule__c = feeSchedule.Id;
                feeScheduleOppService.OpportunityService__c = oppService.Id;

                feeScheduleOppService.Name = feeSchedule.Billing_Date__c != null ? feeSchedule.Name : oppService.Service_Name__c;
                feeScheduleOppService.Price__c = 0; // Price should be updated later based on business logic
                feeScheduleOppServiceList.add(feeScheduleOppService);
            }
        }

        if (!feeScheduleOppServiceList.isEmpty()) {
            insert feeScheduleOppServiceList;
            System.debug('Inserted FeeScheduleOpportunityService records: ' + feeScheduleOppServiceList.size());
        }
    }
}


  // This method  is  used  to display  the  fee schedule  data

@AuraEnabled(cacheable = true)
public static Map<String, Object> displayFeeScheduleData(String projectLabel, String recordId) {
    System.debug('recordId: ' + recordId);
    System.debug('projectLabel: ' + projectLabel);

    Map<String, Object> response = new Map<String, Object>();

    // Query Opportunity Services (Internal)
    List<OpportunityService__c> opportunityServices = [
        SELECT Id, Name, Service_Name__c, Fee_Type__c, Opportunity__c, Project_Type__c, Total_fee__c,Account__c
        FROM OpportunityService__c
        WHERE Project_Type__c =: projectLabel AND Opportunity__c =: recordId
    ];
    System.debug('Fetched Opportunity Services: ' + opportunityServices);

    if (opportunityServices.isEmpty()) {
        System.debug('No Opportunity Services found for the given project label and opportunity.');
        response.put('columns', new List<Map<String, Object>>());
        response.put('rows', new List<Map<String, Object>>());
        response.put('opportunityServices', new List<Map<String, Object>>());
        return response;
    }

    // Map Opportunity Services by ID
    Set<String> serviceName = new Set<String>(); 
    Map<Id, OpportunityService__c> opportunityServiceMap = new Map<Id, OpportunityService__c>();
    for (OpportunityService__c oppService : opportunityServices) {
        opportunityServiceMap.put(oppService.Id, oppService);
    }

    // Add the Boolean flag to each OpportunityService__c
    List<Map<String, Object>> opportunityServiceDetails = new List<Map<String, Object>>();
    for (OpportunityService__c oppService : opportunityServices) {
        Map<String, Object> oppServiceDetails = new Map<String, Object>();
        oppServiceDetails.put('Id', oppService.Id);
        oppServiceDetails.put('Name', oppService.Name);
        oppServiceDetails.put('Fee_Type__c', oppService.Fee_Type__c);
        oppServiceDetails.put('Account__c', oppService.Account__c);
        oppServiceDetails.put('Total_Fee__c', oppService.Total_fee__c);
        oppServiceDetails.put('IsExternal', oppService.Fee_Type__c == 'External'); // Add the boolean flag
        opportunityServiceDetails.add(oppServiceDetails);
    }
    response.put('opportunityServices', opportunityServiceDetails);

    // Remaining code for Fee_Schedule__c and FeeScheduleOpportunityService__c
    List<Fee_Schedule__c> listoffeeschedule = [SELECT Id, Name, Total_Fee__c, Opportunity__c, Project_Type__c
                                               FROM Fee_Schedule__c 
                                               WHERE Opportunity__c = :recordId AND Project_Type__c = :projectLabel];
    Set<Id> feescheduleid = new Set<Id>();
    for (Fee_Schedule__c fc : listoffeeschedule) {
        feescheduleid.add(fc.Id);  
    }

    List<FeeScheduleOpportunityService__c> feeScheduleOppServices = [
        SELECT Id, Fee_Schedule__r.MonthAndYear__c, Fee_Schedule__r.Total_fee__c, OpportunityService__c, Price__c, Fee_Schedule__c
        FROM FeeScheduleOpportunityService__c
        WHERE OpportunityService__c IN :opportunityServiceMap.keySet() AND Fee_Schedule__c IN :feescheduleid
    ];
    System.debug('Fetched FeeScheduleOpportunityService records: ' + feeScheduleOppServices);

    Map<String, Map<String, Object>> rowsByBillingDate = new Map<String, Map<String, Object>>();

    for (FeeScheduleOpportunityService__c fso : feeScheduleOppServices) {
        String monthYear = fso.Fee_Schedule__r.MonthAndYear__c;
        Id serviceId = fso.OpportunityService__c;

        if (monthYear == null || !opportunityServiceMap.containsKey(serviceId)) {
            continue;
        }

        // Initialize a row for the billing date if not already present
        if (!rowsByBillingDate.containsKey(monthYear)) {
            rowsByBillingDate.put(monthYear, new Map<String, Object> {
                'BillingDate' => monthYear,
                'rowtotal' => fso.Fee_Schedule__r.Total_fee__c,
                'id' => fso.Fee_Schedule__c
            });
        }

        // Retrieve related Opportunity Service
        OpportunityService__c oppService = opportunityServiceMap.get(serviceId);

        // Dynamically add Opportunity Service details under its label
        String serviceKey = 'OpportunityService_' + serviceId;
        Map<String, Object> serviceData = new Map<String, Object> {
            'FeeScheduleOpportunityServiceId' => fso.Id,
            'Price__c' => fso.Price__c,
            'FeeScheduleId' => fso.Fee_Schedule__c
        };

        if (oppService != null) {
            serviceData.put('Name', oppService.Name);
            serviceData.put('Fee_Type__c', oppService.Fee_Type__c);
        }

        rowsByBillingDate.get(monthYear).put(serviceKey, serviceData);
    }

    // Prepare rows in the required format
    List<Map<String, Object>> rows = new List<Map<String, Object>>();

    for (String billingDate : rowsByBillingDate.keySet()) {
        rows.add(rowsByBillingDate.get(billingDate));
    }

    // Prepare columns dynamically based on Opportunity Services
    Set<String> columnKeys = new Set<String>();

    for (Map<String, Object> row : rows) {
        columnKeys.addAll(row.keySet());
    }

    // Define base columns
    List<Map<String, Object>> columns = new List<Map<String, Object>>();

    // Add columns for Opportunity Services dynamically with the correct Name
    for (String key : columnKeys) {
        if (key.startsWith('OpportunityService_')) {
            // Extract the OpportunityService ID from the key
            String serviceId = key.substring('OpportunityService_'.length());
            OpportunityService__c oppService = opportunityServiceMap.get(serviceId);

            if (oppService != null) {
                columns.add(new Map<String, Object> {
                    'label' => oppService.Name, // Use the Name field of OpportunityService
                    'fieldName' => key,
                    'type' => 'text',
                    'oppservicetotal' => oppService.Total_fee__c,
                    'feetype' => oppService.Fee_Type__c,
                     'projecttype'=>oppService.Project_Type__c,
                    'opportunityserviceid' => oppService.Id
                        
                });
            }
        }
    }

    // Update the response with formatted columns and rows
    response.put('columns', columns);
    response.put('rows', rows);

    System.debug('Refactored Columns: ' + columns);
    System.debug('Refactored Rows: ' + rows);

    return response;
}

//To display  the  account in lookup 

@AuraEnabled(cacheable=true)
public static List<Account> getAccountList(String searchTerm) {

    return [
        SELECT Id, Name 
        FROM Account 
        WHERE Name LIKE :'searchTerm%'
        LIMIT 100
    ];
}



//To  display the  summary 
 @AuraEnabled(cacheable=true)
    public static List<Opportunity> getOpportunities(Id accountId) {
        return [
            SELECT Name, Total_Internal_Fee__c, Total_External_Fee__c
            FROM Opportunity
            WHERE AccountId = :accountId
        ];
    }
  
}