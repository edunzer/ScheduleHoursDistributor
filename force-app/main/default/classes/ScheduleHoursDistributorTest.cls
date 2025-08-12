@isTest
public class ScheduleHoursDistributorTest {
    @testSetup
    static void setupTestData() {
        // Create a Schedule record
        pse__Schedule__c schedule = new pse__Schedule__c(
            pse__Start_Date__c = Date.newInstance(2025, 1, 1),
            pse__End_Date__c = Date.newInstance(2025, 7, 1),
            pse__Scheduled_Hours__c = 200,
            pse__Monday_Hours__c = 8,
            pse__Tuesday_Hours__c = 8,
            pse__Wednesday_Hours__c = 8,
            pse__Thursday_Hours__c = 8,
            pse__Friday_Hours__c = 8,
            pse__Saturday_Hours__c = 8,
            pse__Sunday_Hours__c = 8
        );
        insert schedule;
    }

    @isTest
    static void testGenerateScheduleExceptions() {
        // Retrieve the created Schedule
        pse__Schedule__c schedule = [SELECT Id, pse__Start_Date__c, pse__End_Date__c, pse__Scheduled_Hours__c FROM pse__Schedule__c LIMIT 1];
        
        // Create input
        ScheduleHoursDistributor.ScheduleInput input = new ScheduleHoursDistributor.ScheduleInput();
        input.scheduleId = schedule.Id;
        input.startDate = schedule.pse__Start_Date__c;
        input.endDate = schedule.pse__End_Date__c;
        input.numberOfHours = schedule.pse__Scheduled_Hours__c;
        input.numberOfWorkDays = 5;
        input.cat1Weeks = 11;
        input.cat2Weeks = 8;
        input.cat3Weeks = 6;
        input.postWeeks = 4;
        input.cat1Percentage = 25;
        input.cat2Percentage = 30;
        input.cat3Percentage = 40;
        input.postPercentage = 5;
        // Add onsite dates for all tests
        input.onsiteStartDate = Date.newInstance(2025, 3, 1);
        input.onsiteEndDate = Date.newInstance(2025, 3, 14);
        input.existingExceptions = new List<pse__Schedule_Exception__c>();

        List<ScheduleHoursDistributor.ScheduleExceptionOutputWrapper> result = ScheduleHoursDistributor.generateCategoryScheduleExceptions(new List<ScheduleHoursDistributor.ScheduleInput>{input});

        // Assertions
        System.assertNotEquals(null, result, 'Result should not be null');
        System.assertEquals(1, result.size(), 'Only one result should be returned');
        System.assert(result[0].scheduleExceptions.size() > 0, 'Schedule exceptions should be generated');
        System.assertEquals(null, result[0].errorMessage, 'There should be no error messages');
    }

    @isTest
    static void testGenerateScheduleExceptionsWithNullScheduleId() {
        // Create input with null scheduleId
        ScheduleHoursDistributor.ScheduleInput input = new ScheduleHoursDistributor.ScheduleInput();
        input.scheduleId = null;
        input.startDate = Date.newInstance(2025, 1, 1);
        input.endDate = Date.newInstance(2025, 7, 1);
        input.numberOfHours = 200;
        input.numberOfWorkDays = 5;
        input.cat1Weeks = 11;
        input.cat2Weeks = 8;
        input.cat3Weeks = 6;
        input.postWeeks = 4;
        input.cat1Percentage = 25;
        input.cat2Percentage = 30;
        input.cat3Percentage = 40;
        input.postPercentage = 5;
        // Add onsite dates for all tests
        input.onsiteStartDate = Date.newInstance(2025, 3, 1);
        input.onsiteEndDate = Date.newInstance(2025, 3, 14);
        input.existingExceptions = new List<pse__Schedule_Exception__c>();

        List<ScheduleHoursDistributor.ScheduleExceptionOutputWrapper> result = ScheduleHoursDistributor.generateCategoryScheduleExceptions(new List<ScheduleHoursDistributor.ScheduleInput>{input});

        // Assertions
        System.assertNotEquals(null, result, 'Result should not be null');
        System.assertEquals(1, result.size(), 'Only one result should be returned');
        System.assertEquals(0, result[0].scheduleExceptions.size(), 'No schedule exceptions should be generated');
        System.assertNotEquals(null, result[0].errorMessage, 'An error message should be present');
        System.assertEquals('Error: Schedule ID cannot be null.', result[0].errorMessage, 'Error message should match expected output');
    }
}