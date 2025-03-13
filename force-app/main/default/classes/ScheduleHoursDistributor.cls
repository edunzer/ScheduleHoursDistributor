public with sharing class ScheduleHoursDistributor {
    
    @InvocableMethod(label='Generate Schedule Exceptions' description='Calculates and returns Schedule Exception records without inserting them.')
    public static List<ScheduleExceptionOutputWrapper> generateScheduleExceptions(List<ScheduleInput> inputList) {
        if (inputList.isEmpty()) {
            return new List<ScheduleExceptionOutputWrapper>();
        }

        ScheduleInput input = inputList[0];

        // Step 1: Calculate total number of weeks (sum of all category weeks)
        Decimal totalWeeks = input.cat1Weeks + input.cat2Weeks + input.cat3Weeks + input.postWeeks;

        // Step 2: Calculate hours per week for each category
        Decimal hoursPerWeekCat1 = (input.cat1Percentage / 100) * input.numberOfHours / input.cat1Weeks;
        Decimal hoursPerWeekCat2 = (input.cat2Percentage / 100) * input.numberOfHours / input.cat2Weeks;
        Decimal hoursPerWeekCat3 = (input.cat3Percentage / 100) * input.numberOfHours / input.cat3Weeks;
        Decimal hoursPerWeekPost = (input.postPercentage / 100) * input.numberOfHours / input.postWeeks;

        // Step 3: Generate schedule exception records
        List<pse__Schedule_Exception__c> exceptions = generateExceptions(
            input, hoursPerWeekCat1, hoursPerWeekCat2, hoursPerWeekCat3, hoursPerWeekPost
        );

        // Step 4: Wrap and return with calculated hours per category
        return new List<ScheduleExceptionOutputWrapper>{ 
            new ScheduleExceptionOutputWrapper(exceptions, hoursPerWeekCat1, hoursPerWeekCat2, hoursPerWeekCat3, hoursPerWeekPost)
        };
    }

    // Generate schedule exceptions dynamically based on category-specific weeks
    private static List<pse__Schedule_Exception__c> generateExceptions(
        ScheduleInput input, Decimal hoursPerWeekCat1, Decimal hoursPerWeekCat2, 
        Decimal hoursPerWeekCat3, Decimal hoursPerWeekPost
    ) {
        List<pse__Schedule_Exception__c> exceptions = new List<pse__Schedule_Exception__c>();
        Date currentStartDate = input.startDate;
        Integer currentWeek = 0;

        // Track assigned weeks for each category
        Integer allocatedCat1Weeks = 0;
        Integer allocatedCat2Weeks = 0;
        Integer allocatedCat3Weeks = 0;
        Integer allocatedPostWeeks = 0;

        while (currentStartDate <= input.endDate && currentWeek < (input.cat1Weeks + input.cat2Weeks + input.cat3Weeks + input.postWeeks)) {
            Date currentEndDate = currentStartDate.addDays(6);
            if (currentEndDate > input.endDate) {
                currentEndDate = input.endDate;
            }

            // Step 4: Assign the correct category based on the allocated weeks
            Decimal hoursPerWeek;
            String category;
            if (allocatedCat1Weeks < input.cat1Weeks) {
                category = 'Cat1';
                hoursPerWeek = hoursPerWeekCat1;
                allocatedCat1Weeks++;
            } else if (allocatedCat2Weeks < input.cat2Weeks) {
                category = 'Cat2';
                hoursPerWeek = hoursPerWeekCat2;
                allocatedCat2Weeks++;
            } else if (allocatedCat3Weeks < input.cat3Weeks) {
                category = 'Cat3';
                hoursPerWeek = hoursPerWeekCat3;
                allocatedCat3Weeks++;
            } else {
                category = 'Post';
                hoursPerWeek = hoursPerWeekPost;
                allocatedPostWeeks++;
            }

            // Step 5: Distribute hours per week across workdays
            Decimal hoursPerDay = hoursPerWeek / input.numberOfWorkDays;

            // Create schedule exception record
            exceptions.add(createScheduleException(input.scheduleId, currentStartDate, currentEndDate, input.numberOfWorkDays, hoursPerDay));

            // Move to next week
            currentStartDate = currentStartDate.addDays(7);
            currentWeek++;
        }

        return exceptions;
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

    // Wrapper class to properly expose output collection for Flow with extra outputs
    public class ScheduleExceptionOutputWrapper {
        @InvocableVariable(label='Schedule Exceptions' description='List of Schedule Exception records')
        public List<pse__Schedule_Exception__c> scheduleExceptions;

        @InvocableVariable(label='Hours Per Week - Cat1' description='Calculated hours per week for Category 1')
        public Decimal hoursPerWeekCat1;

        @InvocableVariable(label='Hours Per Week - Cat2' description='Calculated hours per week for Category 2')
        public Decimal hoursPerWeekCat2;

        @InvocableVariable(label='Hours Per Week - Cat3' description='Calculated hours per week for Category 3')
        public Decimal hoursPerWeekCat3;

        @InvocableVariable(label='Hours Per Week - Post' description='Calculated hours per week for Post Category')
        public Decimal hoursPerWeekPost;

        public ScheduleExceptionOutputWrapper(List<pse__Schedule_Exception__c> exceptions, Decimal cat1Hours, Decimal cat2Hours, Decimal cat3Hours, Decimal postHours) {
            this.scheduleExceptions = exceptions;
            this.hoursPerWeekCat1 = cat1Hours;
            this.hoursPerWeekCat2 = cat2Hours;
            this.hoursPerWeekCat3 = cat3Hours;
            this.hoursPerWeekPost = postHours;
        }
    }

    // Invocable Variable Class for Flow Inputs
    public class ScheduleInput {
        @InvocableVariable(label='Schedule ID') public Id scheduleId;
        @InvocableVariable(label='Start Date') public Date startDate;
        @InvocableVariable(label='End Date') public Date endDate;
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
