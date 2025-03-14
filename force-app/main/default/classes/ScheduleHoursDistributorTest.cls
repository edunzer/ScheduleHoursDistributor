@isTest
public with sharing class ScheduleHoursDistributorTest {

    @isTest
    public static void testGenerateScheduleExceptions_ValidInput() {
        // Create a test Schedule record
        pse__Schedule__c testSchedule = new pse__Schedule__c(
            pse__Start_Date__c = Date.newInstance(2025, 1, 1),
            pse__End_Date__c = Date.newInstance(2025, 7, 1),
            pse__Scheduled_Hours__c = 200
        );
        insert testSchedule;
        Id scheduleId = testSchedule.Id;

        // Prepare the test input
        ScheduleHoursDistributor.ScheduleInput input = new ScheduleHoursDistributor.ScheduleInput();
        input.scheduleId = scheduleId;
        input.startDate = testSchedule.pse__Start_Date__c;
        input.endDate = testSchedule.pse__End_Date__c;
        input.numberOfHours = testSchedule.pse__Scheduled_Hours__c;
        input.numberOfWorkDays = 5; // Valid workdays
        input.cat1Weeks = 8;
        input.cat2Weeks = 8;
        input.cat3Weeks = 6;
        input.postWeeks = 4;
        input.cat1Percentage = 25;
        input.cat2Percentage = 30;
        input.cat3Percentage = 40;
        input.postPercentage = 5;
        input.existingExceptions = new List<pse__Schedule_Exception__c>(); // No existing exceptions

        // Execute Method
        List<ScheduleHoursDistributor.ScheduleExceptionOutputWrapper> results = 
            ScheduleHoursDistributor.generateScheduleExceptions(new List<ScheduleHoursDistributor.ScheduleInput>{ input });

        // Assertions
        System.assertNotEquals(null, results, 'Results should not be null');
        System.assertEquals(1, results.size(), 'Should return one wrapper object');
        System.assertNotEquals(null, results[0].scheduleExceptions, 'Schedule Exceptions list should not be null');
        System.assert(results[0].scheduleExceptions.size() > 0, 'Should create schedule exceptions');
        System.assertEquals(null, results[0].errorMessage, 'Error message should be null in valid execution');
    }

    @isTest
    public static void testGenerateScheduleExceptions_ZeroWorkDays() {
        // Create a test Schedule record
        pse__Schedule__c testSchedule = new pse__Schedule__c(
            pse__Start_Date__c = Date.newInstance(2025, 1, 1),
            pse__End_Date__c = Date.newInstance(2025, 7, 1),
            pse__Scheduled_Hours__c = 200
        );
        insert testSchedule;

        // Prepare input with zero workdays
        ScheduleHoursDistributor.ScheduleInput input = new ScheduleHoursDistributor.ScheduleInput();
        input.scheduleId = testSchedule.Id;
        input.startDate = testSchedule.pse__Start_Date__c;
        input.endDate = testSchedule.pse__End_Date__c;
        input.numberOfHours = testSchedule.pse__Scheduled_Hours__c;
        input.numberOfWorkDays = 0; // Invalid case
        input.cat1Weeks = 8;
        input.cat2Weeks = 8;
        input.cat3Weeks = 6;
        input.postWeeks = 4;
        input.cat1Percentage = 25;
        input.cat2Percentage = 30;
        input.cat3Percentage = 40;
        input.postPercentage = 5;
        input.existingExceptions = null;

        // Execute Method
        List<ScheduleHoursDistributor.ScheduleExceptionOutputWrapper> results = 
            ScheduleHoursDistributor.generateScheduleExceptions(new List<ScheduleHoursDistributor.ScheduleInput>{ input });

        // Assertions
        System.assertNotEquals(null, results, 'Results should not be null');
        System.assertEquals(1, results.size(), 'Should return one wrapper object');
        System.assertEquals(0, results[0].scheduleExceptions.size(), 'Should not generate schedule exceptions');
        System.assertNotEquals(null, results[0].errorMessage, 'Error message should be returned for zero workdays');
        System.assertEquals('Error: Number of work days is zero, cannot calculate hours per day.', 
                            results[0].errorMessage, 'Expected error message for zero workdays');
    }

    @isTest
    public static void testGenerateScheduleExceptions_NoHoursAssigned() {
        // Create a test Schedule record
        pse__Schedule__c testSchedule = new pse__Schedule__c(
            pse__Start_Date__c = Date.newInstance(2025, 1, 1),
            pse__End_Date__c = Date.newInstance(2025, 7, 1),
            pse__Scheduled_Hours__c = 0 // No hours assigned
        );
        insert testSchedule;

        // Prepare input with zero scheduled hours
        ScheduleHoursDistributor.ScheduleInput input = new ScheduleHoursDistributor.ScheduleInput();
        input.scheduleId = testSchedule.Id;
        input.startDate = testSchedule.pse__Start_Date__c;
        input.endDate = testSchedule.pse__End_Date__c;
        input.numberOfHours = 0; // No hours
        input.numberOfWorkDays = 5;
        input.cat1Weeks = 8;
        input.cat2Weeks = 8;
        input.cat3Weeks = 6;
        input.postWeeks = 4;
        input.cat1Percentage = 25;
        input.cat2Percentage = 30;
        input.cat3Percentage = 40;
        input.postPercentage = 5;
        input.existingExceptions = null;

        // Execute Method
        List<ScheduleHoursDistributor.ScheduleExceptionOutputWrapper> results = 
            ScheduleHoursDistributor.generateScheduleExceptions(new List<ScheduleHoursDistributor.ScheduleInput>{ input });

        // Assertions
        System.assertNotEquals(null, results, 'Results should not be null');
        System.assertEquals(1, results.size(), 'Should return one wrapper object');
        System.assertEquals(0, results[0].scheduleExceptions.size(), 'Should not generate schedule exceptions');
        System.assertEquals(null, results[0].errorMessage, 'No error message expected since it returns an empty list');
    }

    @isTest
    public static void testGenerateScheduleExceptions_ExceptionHandling() {
        // Create an input that will cause an exception
        ScheduleHoursDistributor.ScheduleInput input = new ScheduleHoursDistributor.ScheduleInput();
        input.scheduleId = null; // Invalid scenario
        input.startDate = null;
        input.endDate = null;
        input.numberOfHours = null;
        input.numberOfWorkDays = null;
        input.cat1Weeks = null;
        input.cat2Weeks = null;
        input.cat3Weeks = null;
        input.postWeeks = null;
        input.cat1Percentage = null;
        input.cat2Percentage = null;
        input.cat3Percentage = null;
        input.postPercentage = null;
        input.existingExceptions = null;

        // Execute Method
        List<ScheduleHoursDistributor.ScheduleExceptionOutputWrapper> results = 
            ScheduleHoursDistributor.generateScheduleExceptions(new List<ScheduleHoursDistributor.ScheduleInput>{ input });

        // Assertions
        System.assertNotEquals(null, results, 'Results should not be null');
        System.assertEquals(1, results.size(), 'Should return one wrapper object');
        System.assertEquals(0, results[0].scheduleExceptions.size(), 'Should not generate schedule exceptions');
        System.assertNotEquals(null, results[0].errorMessage, 'Error message should be present');
    }
}
