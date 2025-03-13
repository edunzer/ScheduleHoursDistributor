public with sharing class ScheduleHoursDistributor {
    
    @InvocableMethod(label='Generate Schedule Exceptions' description='Calculates and returns Schedule Exception records without inserting them.')
    public static List<ScheduleExceptionOutput> generateScheduleExceptions(List<ScheduleInput> inputList) {
        if (inputList.isEmpty()) {
            return new List<ScheduleExceptionOutput>();
        }

        ScheduleInput input = inputList[0];

        // Step 1: Calculate weeks per category
        Map<String, Decimal> categoryWeeks = calculateCategoryWeeks(input);

        // Step 2: Calculate hours per week for each category
        Map<String, Decimal> hoursPerWeek = calculateHoursPerWeek(input, categoryWeeks);

        // Step 3: Generate schedule exception records
        List<Schedule_Exception__c> exceptions = generateExceptions(input, categoryWeeks, hoursPerWeek);

        // Convert to output wrapper for Flow compatibility
        List<ScheduleExceptionOutput> outputList = new List<ScheduleExceptionOutput>();
        for (Schedule_Exception__c ex : exceptions) {
            ScheduleExceptionOutput outputRecord = new ScheduleExceptionOutput();
            outputRecord.scheduleException = ex;
            outputList.add(outputRecord);
        }

        return outputList;
    }

    // Calculate the number of weeks allocated to each category
    private static Map<String, Decimal> calculateCategoryWeeks(ScheduleInput input) {
        Decimal totalWeeks = input.numberOfWeeks;
        return new Map<String, Decimal>{
            'Pre' => (input.prePercentage / 100) * totalWeeks,
            'Planning' => (input.planningPercentage / 100) * totalWeeks,
            'Pre-Onsite' => (input.preOnsitePercentage / 100) * totalWeeks,
            'Post' => (input.postPercentage / 100) * totalWeeks
        };
    }

    // Calculate hours per week based on the category's percentage
    private static Map<String, Decimal> calculateHoursPerWeek(ScheduleInput input, Map<String, Decimal> categoryWeeks) {
        Decimal totalHours = input.numberOfHours;
        Decimal totalWeeks = input.numberOfWeeks;
        return new Map<String, Decimal>{
            'Pre' => (totalHours * (input.prePercentage / 100)) / totalWeeks,
            'Planning' => (totalHours * (input.planningPercentage / 100)) / totalWeeks,
            'Pre-Onsite' => (totalHours * (input.preOnsitePercentage / 100)) / totalWeeks,
            'Post' => (totalHours * (input.postPercentage / 100)) / totalWeeks
        };
    }

    // Generate schedule exceptions dynamically for each week
    private static List<Schedule_Exception__c> generateExceptions(ScheduleInput input, Map<String, Decimal> categoryWeeks, Map<String, Decimal> hoursPerWeek) {
        List<Schedule_Exception__c> exceptions = new List<Schedule_Exception__c>();
        Date currentStartDate = input.startDate;
        Integer currentWeek = 0;

        Map<String, Decimal> allocatedWeeks = new Map<String, Decimal>{
            'Pre' => 0, 'Planning' => 0, 'Pre-Onsite' => 0, 'Post' => 0
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
    private static Schedule_Exception__c createScheduleException(Id scheduleId, Date startDate, Date endDate, Integer workDays, Decimal hoursPerDay) {
        return new Schedule_Exception__c(
            Schedule__c = scheduleId,
            Start_Date__c = startDate,
            End_Date__c = endDate,
            Monday__c = (workDays >= 1) ? hoursPerDay : 0,
            Tuesday__c = (workDays >= 2) ? hoursPerDay : 0,
            Wednesday__c = (workDays >= 3) ? hoursPerDay : 0,
            Thursday__c = (workDays >= 4) ? hoursPerDay : 0,
            Friday__c = (workDays >= 5) ? hoursPerDay : 0,
            Saturday__c = (workDays >= 6) ? hoursPerDay : 0,
            Sunday__c = (workDays >= 7) ? hoursPerDay : 0
        );
    }

    // Wrapper class to expose the output collection to Flow
    public class ScheduleExceptionOutput {
        @InvocableVariable(label='Schedule Exception Record' description='Generated Schedule Exception record')
        public Schedule_Exception__c scheduleException;
    }

    // Invocable Variable Class for Flow Inputs
    public class ScheduleInput {
        @InvocableVariable(label='Schedule ID') public Id scheduleId;
        @InvocableVariable(label='Start Date') public Date startDate;
        @InvocableVariable(label='End Date') public Date endDate;
        @InvocableVariable(label='Number of Weeks') public Decimal numberOfWeeks;
        @InvocableVariable(label='Number of Hours') public Decimal numberOfHours;
        @InvocableVariable(label='Number of Work Days') public Integer numberOfWorkDays;
        @InvocableVariable(label='Pre Percentage') public Decimal prePercentage;
        @InvocableVariable(label='Planning Percentage') public Decimal planningPercentage;
        @InvocableVariable(label='Pre-Onsite Percentage') public Decimal preOnsitePercentage;
        @InvocableVariable(label='Post Percentage') public Decimal postPercentage;
    }
}
