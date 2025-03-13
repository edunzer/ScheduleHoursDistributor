public with sharing class ScheduleHoursDistributor {
    
    @InvocableMethod(label='Generate Schedule Exceptions' description='Calculates and returns Schedule Exception records without inserting them.')
    public static List<ScheduleExceptionOutputWrapper> generateScheduleExceptions(List<ScheduleInput> inputList) {
        if (inputList.isEmpty()) {
            return new List<ScheduleExceptionOutputWrapper>();
        }

        ScheduleInput input = inputList[0];

        // Step 1: Use provided weeks per category
        Map<String, Decimal> categoryWeeks = new Map<String, Decimal>{
            'Cat1' => input.cat1Weeks,
            'Cat2' => input.cat2Weeks,
            'Cat3' => input.cat3Weeks,
            'Post' => input.postWeeks
        };

        // Step 2: Calculate hours per week based on provided percentages
        Map<String, Decimal> hoursPerWeek = calculateHoursPerWeek(input, categoryWeeks);

        // Step 3: Generate schedule exception records
        List<pse__Schedule_Exception__c> exceptions = generateExceptions(input, categoryWeeks, hoursPerWeek);

        // Step 4: Wrap the list and return as a collection variable
        return new List<ScheduleExceptionOutputWrapper>{ new ScheduleExceptionOutputWrapper(exceptions) };
    }

    // Calculate hours per week based on provided percentages
    private static Map<String, Decimal> calculateHoursPerWeek(ScheduleInput input, Map<String, Decimal> categoryWeeks) {
        Decimal totalHours = input.numberOfHours;
        Decimal totalWeeks = input.cat1Weeks + input.cat2Weeks + input.cat3Weeks + input.postWeeks;
        return new Map<String, Decimal>{
            'Cat1' => (totalHours * (input.cat1Percentage / 100)) / input.cat1Weeks,
            'Cat2' => (totalHours * (input.cat2Percentage / 100)) / input.cat2Weeks,
            'Cat3' => (totalHours * (input.cat3Percentage / 100)) / input.cat3Weeks,
            'Post' => (totalHours * (input.postPercentage / 100)) / input.postWeeks
        };
    }

    // Generate schedule exceptions dynamically for each week
    private static List<pse__Schedule_Exception__c> generateExceptions(ScheduleInput input, Map<String, Decimal> categoryWeeks, Map<String, Decimal> hoursPerWeek) {
        List<pse__Schedule_Exception__c> exceptions = new List<pse__Schedule_Exception__c>();
        Date currentStartDate = input.startDate;
        Integer currentWeek = 0;

        Map<String, Decimal> allocatedWeeks = new Map<String, Decimal>{
            'Cat1' => 0, 'Cat2' => 0, 'Cat3' => 0, 'Post' => 0
        };

        while (currentStartDate <= input.endDate && currentWeek < input.numberOfWeeks) {
            Date currentEndDate = currentStartDate.addDays(6);
            if (currentEndDate > input.endDate) {
                currentEndDate = input.endDate;
            }

            // Step 4: Determine category and hours for this week
            String category = determineCategory(categoryWeeks, allocatedWeeks);
            Decimal hoursPerDay = hoursPerWeek.get(category) / input.numberOfWorkDays;
            allocatedWeeks.put(category, allocatedWeeks.get(category) + 1);

            // Step 5: Create schedule exception record
            exceptions.add(createScheduleException(input.scheduleId, currentStartDate, currentEndDate, input.numberOfWorkDays, hoursPerDay));

            // Move to next week
            currentStartDate = currentStartDate.addDays(7);
            currentWeek++;
        }

        return exceptions;
    }

    // Determine which category should be assigned for the current week
    private static String determineCategory(Map<String, Decimal> categoryWeeks, Map<String, Decimal> allocatedWeeks) {
        for (String category : categoryWeeks.keySet()) {
            if (allocatedWeeks.get(category) < categoryWeeks.get(category)) {
                return category;
            }
        }
        return 'Post'; // Default to 'Post' if others are filled
    }

    // Create and return a Schedule Exception record (does not insert)
    private static pse__Schedule_Exception__c createScheduleException(Id scheduleId, Date startDate, Date endDate, Integer workDays, Decimal hoursPerDay) {
        return new pse__Schedule_Exception__c(
            pse__Schedule__c = scheduleId,
            pse__Date__c = startDate,
            pse__End_Date__c = endDate,
            pse__Monday_Hours__c = (workDays >= 1) ? hoursPerDay : 0,
            pse__Tuesday_Hours__c = (workDays >= 2) ? hoursPerDay : 0,
            pse__Wednesday_Hours__c = (workDays >= 3) ? hoursPerDay : 0,
            pse__Thursday_Hours__c = (workDays >= 4) ? hoursPerDay : 0,
            pse__Friday_Hours__c = (workDays >= 5) ? hoursPerDay : 0,
            pse__Saturday_Hours__c = (workDays >= 6) ? hoursPerDay : 0,
            pse__Sunday_Hours__c = (workDays >= 7) ? hoursPerDay : 0
        );
    }

    // Wrapper class to properly expose output collection for Flow
    public class ScheduleExceptionOutputWrapper {
        @InvocableVariable(label='Schedule Exceptions' description='List of Schedule Exception records')
        public List<pse__Schedule_Exception__c> scheduleExceptions;

        public ScheduleExceptionOutputWrapper(List<pse__Schedule_Exception__c> exceptions) {
            this.scheduleExceptions = exceptions;
        }
    }

    // Invocable Variable Class for Flow Inputs
    public class ScheduleInput {
        @InvocableVariable(label='Schedule ID') public Id scheduleId;
        @InvocableVariable(label='Start Date') public Date startDate;
        @InvocableVariable(label='End Date') public Date endDate;
        @InvocableVariable(label='Number of Weeks') public Decimal numberOfWeeks;
        @InvocableVariable(label='Number of Hours') public Decimal numberOfHours;
        @InvocableVariable(label='Number of Work Days') public Integer numberOfWorkDays;
        
        // New direct week inputs
        @InvocableVariable(label='Category 1 Weeks') public Decimal cat1Weeks;
        @InvocableVariable(label='Category 2 Weeks') public Decimal cat2Weeks;
        @InvocableVariable(label='Category 3 Weeks') public Decimal cat3Weeks;
        @InvocableVariable(label='Post Weeks') public Decimal postWeeks;

        // Percentage inputs for hours distribution
        @InvocableVariable(label='Category 1 Percentage') public Decimal cat1Percentage;
        @InvocableVariable(label='Category 2 Percentage') public Decimal cat2Percentage;
        @InvocableVariable(label='Category 3 Percentage') public Decimal cat3Percentage;
        @InvocableVariable(label='Post Percentage') public Decimal postPercentage;
    }
}
