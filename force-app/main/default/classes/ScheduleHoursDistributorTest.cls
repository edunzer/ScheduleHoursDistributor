@isTest
private class ScheduleHoursDistributorTest {

    @isTest
    static void testGenerateScheduleExceptions() {
        // Create test ScheduleInput
        ScheduleHoursDistributor.ScheduleInput input = new ScheduleHoursDistributor.ScheduleInput();
        input.scheduleId = Id.valueOf('001000000000000AAA');
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
        input.existingExceptions = new List<pse__Schedule_Exception__c>();

        List<ScheduleHoursDistributor.ScheduleInput> inputs = new List<ScheduleHoursDistributor.ScheduleInput>{input};
        
        Test.startTest();
        List<ScheduleHoursDistributor.ScheduleExceptionOutputWrapper> results = ScheduleHoursDistributor.generateScheduleExceptions(inputs);
        Test.stopTest();
        
        System.assertNotEquals(null, results, 'Results should not be null');
        System.assertEquals(1, results.size(), 'There should be one result wrapper');
        System.assertNotEquals(null, results[0].scheduleExceptions, 'Schedule Exceptions list should not be null');
        System.assert(results[0].scheduleExceptions.size() > 0, 'Schedule Exceptions should be generated');
    }

    @isTest
    static void testNullInputs() {
        // Test null scheduleId
        ScheduleHoursDistributor.ScheduleInput input = new ScheduleHoursDistributor.ScheduleInput();
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
        
        List<ScheduleHoursDistributor.ScheduleInput> inputs = new List<ScheduleHoursDistributor.ScheduleInput>{input};
        
        Test.startTest();
        List<ScheduleHoursDistributor.ScheduleExceptionOutputWrapper> results = ScheduleHoursDistributor.generateScheduleExceptions(inputs);
        Test.stopTest();
        
        System.assertNotEquals(null, results, 'Results should not be null');
        System.assertEquals(1, results.size(), 'There should be one result wrapper');
        System.assertNotEquals(null, results[0].errorMessage, 'Error message should be returned for null scheduleId');
    }
}
