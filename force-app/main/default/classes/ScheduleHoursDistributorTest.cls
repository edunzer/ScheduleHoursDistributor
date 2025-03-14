@isTest
public with sharing class ScheduleHoursDistributorTest {
    
    @isTest
    public static void testGenerateScheduleExceptions() {
        // Test Data Setup - Create a test Schedule record
        pse__Schedule__c testSchedule = new pse__Schedule__c(
            pse__Start_Date__c = Date.newInstance(2025, 1, 1),
            pse__End_Date__c = Date.newInstance(2025, 7, 1),
            pse__Scheduled_Hours__c = 200,
            pse__Monday_Hours__c = 8,
            pse__Tuesday_Hours__c = 8,
            pse__Wednesday_Hours__c = 8,
            pse__Thursday_Hours__c = 8,
            pse__Friday_Hours__c = 8,
            pse__Saturday_Hours__c = 0,
            pse__Sunday_Hours__c = 0
        );
        insert testSchedule;
        Id scheduleId = testSchedule.Id;

        // Create Schedule Input for the test
        ScheduleHoursDistributor.ScheduleInput input = new ScheduleHoursDistributor.ScheduleInput();
        input.scheduleId = scheduleId;
        input.startDate = testSchedule.pse__Start_Date__c;
        input.endDate = testSchedule.pse__End_Date__c;
        input.numberOfHours = testSchedule.pse__Scheduled_Hours__c;
        input.numberOfWorkDays = 5;
        input.cat1Weeks = 8;
        input.cat2Weeks = 8;
        input.cat3Weeks = 6;
        input.postWeeks = 4;
        input.cat1Percentage = 0.25;
        input.cat2Percentage = 0.30;
        input.cat3Percentage = 0.40;
        input.postPercentage = 0.05;

        // Execute Method
        List<ScheduleHoursDistributor.ScheduleExceptionOutputWrapper> results = ScheduleHoursDistributor.generateScheduleExceptions(new List<ScheduleHoursDistributor.ScheduleInput>{ input });

        // Assertions
        System.assertNotEquals(null, results, 'Results should not be null');
        System.assertEquals(1, results.size(), 'Should return one wrapper object');
        System.assertNotEquals(null, results[0].scheduleExceptions, 'Schedule Exceptions list should not be null');
        System.assert(results[0].scheduleExceptions.size() > 0, 'Should create schedule exceptions');

        // Validate calculated hours per category (rounded)
        System.assertEquals(6.25, Math.round(results[0].hoursPerWeekCat1), 'Cat1 hours per week should match expected value');
        System.assertEquals(7.50, Math.round(results[0].hoursPerWeekCat2), 'Cat2 hours per week should match expected value');
        System.assertEquals(13.33, Math.round(results[0].hoursPerWeekCat3), 'Cat3 hours per week should match expected value');
        System.assertEquals(2.50, Math.round(results[0].hoursPerWeekPost), 'Post hours per week should match expected value');
    }
}
