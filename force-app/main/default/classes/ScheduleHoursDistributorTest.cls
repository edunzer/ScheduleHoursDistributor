@isTest
public class ScheduleHoursDistributorTest {
    @testSetup
    static void setupTestData() {
        // Create two Schedule records: one that will have exceptions and one that will not
        pse__Schedule__c scheduleWithExceptions = new pse__Schedule__c(
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
        pse__Schedule__c scheduleNoExceptions = new pse__Schedule__c(
            pse__Start_Date__c = Date.newInstance(2026, 1, 1),
            pse__End_Date__c = Date.newInstance(2026, 7, 1),
            pse__Scheduled_Hours__c = 100,
            pse__Monday_Hours__c = 8,
            pse__Tuesday_Hours__c = 8,
            pse__Wednesday_Hours__c = 8,
            pse__Thursday_Hours__c = 8,
            pse__Friday_Hours__c = 8,
            pse__Saturday_Hours__c = 0,
            pse__Sunday_Hours__c = 0
        );
        insert new List<pse__Schedule__c>{ scheduleWithExceptions, scheduleNoExceptions };

        // Reusable zero-hour holiday exceptions (non-overlapping)
        insert new List<pse__Schedule_Exception__c>{
            zeroHourException(scheduleWithExceptions.Id, Date.newInstance(2025, 1, 8), Date.newInstance(2025, 1, 8)),   // single-day
            zeroHourException(scheduleWithExceptions.Id, Date.newInstance(2025, 3, 10), Date.newInstance(2025, 3, 12)), // multi-day (Mon-Wed)
            zeroHourException(scheduleWithExceptions.Id, Date.newInstance(2025, 3, 13), Date.newInstance(2025, 3, 13))  // single-day
        };
    }

    // ---------------------------------------------------------------------
    // Test helpers
    // ---------------------------------------------------------------------

    private static pse__Schedule_Exception__c zeroHourException(Id scheduleId, Date startDate, Date endDate) {
        return new pse__Schedule_Exception__c(
            pse__Schedule__c = scheduleId,
            pse__Date__c = startDate,
            pse__End_Date__c = endDate,
            pse__Monday_Hours__c = 0,
            pse__Tuesday_Hours__c = 0,
            pse__Wednesday_Hours__c = 0,
            pse__Thursday_Hours__c = 0,
            pse__Friday_Hours__c = 0,
            pse__Saturday_Hours__c = 0,
            pse__Sunday_Hours__c = 0
        );
    }

    private static Id schedule2025Id() {
        return [SELECT Id FROM pse__Schedule__c WHERE pse__Start_Date__c = :Date.newInstance(2025, 1, 1) LIMIT 1].Id;
    }

    // Builds an input with Mon-Fri work days, zero weeks / zero percentages and no existing exceptions.
    private static ScheduleHoursDistributor.ScheduleInput buildInput(Id scheduleId, Date startDate, Date endDate, Decimal hours) {
        ScheduleHoursDistributor.ScheduleInput input = new ScheduleHoursDistributor.ScheduleInput();
        input.scheduleId = scheduleId;
        input.startDate = startDate;
        input.endDate = endDate;
        input.numberOfHours = hours;
        input.numberOfWorkDays = 5;
        setWeeks(input, 0, 0, 0, 0);
        setPercentages(input, 0, 0, 0, 0);
        input.existingExceptions = new List<pse__Schedule_Exception__c>();
        return input;
    }

    private static void setWeeks(ScheduleHoursDistributor.ScheduleInput input, Decimal cat1, Decimal cat2, Decimal cat3, Decimal post) {
        input.cat1Weeks = cat1;
        input.cat2Weeks = cat2;
        input.cat3Weeks = cat3;
        input.postWeeks = post;
    }

    private static void setPercentages(ScheduleHoursDistributor.ScheduleInput input, Decimal cat1, Decimal cat2, Decimal cat3, Decimal post) {
        input.cat1Percentage = cat1;
        input.cat2Percentage = cat2;
        input.cat3Percentage = cat3;
        input.postPercentage = post;
    }

    private static List<ScheduleHoursDistributor.ScheduleExceptionOutputWrapper> run(ScheduleHoursDistributor.ScheduleInput input) {
        return ScheduleHoursDistributor.generateCategoryScheduleExceptions(new List<ScheduleHoursDistributor.ScheduleInput>{ input });
    }

    // Hours an exception assigns to a specific date, using locale-independent weekday math.
    private static Decimal hoursOnDate(pse__Schedule_Exception__c exc, Date d) {
        Integer dow = ScheduleHoursDistributor.getNormalizedDayOfWeek(d); // 1=Monday ... 7=Sunday
        Decimal hrs;
        if (dow == 1) hrs = exc.pse__Monday_Hours__c;
        if (dow == 2) hrs = exc.pse__Tuesday_Hours__c;
        if (dow == 3) hrs = exc.pse__Wednesday_Hours__c;
        if (dow == 4) hrs = exc.pse__Thursday_Hours__c;
        if (dow == 5) hrs = exc.pse__Friday_Hours__c;
        if (dow == 6) hrs = exc.pse__Saturday_Hours__c;
        if (dow == 7) hrs = exc.pse__Sunday_Hours__c;
        return hrs == null ? 0 : hrs;
    }

    private static Date endOf(pse__Schedule_Exception__c exc) {
        return exc.pse__End_Date__c == null ? exc.pse__Date__c : exc.pse__End_Date__c;
    }

    // Total hours scheduled across all exceptions on dates within [rangeStart, rangeEnd] (nulls = unbounded).
    private static Decimal sumScheduledHours(List<pse__Schedule_Exception__c> exceptions, Date rangeStart, Date rangeEnd) {
        Decimal total = 0;
        for (pse__Schedule_Exception__c exc : exceptions) {
            for (Date d = exc.pse__Date__c; d <= endOf(exc); d = d.addDays(1)) {
                if ((rangeStart == null || d >= rangeStart) && (rangeEnd == null || d <= rangeEnd)) {
                    total += hoursOnDate(exc, d);
                }
            }
        }
        return total;
    }

    private static Decimal sumScheduledHours(List<pse__Schedule_Exception__c> exceptions) {
        return sumScheduledHours(exceptions, null, null);
    }

    // ---------------------------------------------------------------------
    // Happy path / validation
    // ---------------------------------------------------------------------

    @isTest
    static void testGenerateScheduleExceptions() {
        pse__Schedule__c schedule = [SELECT Id, pse__Start_Date__c, pse__End_Date__c, pse__Scheduled_Hours__c FROM pse__Schedule__c WHERE pse__Start_Date__c = :Date.newInstance(2025, 1, 1) LIMIT 1];

        ScheduleHoursDistributor.ScheduleInput input = buildInput(schedule.Id, schedule.pse__Start_Date__c, schedule.pse__End_Date__c, schedule.pse__Scheduled_Hours__c);
        setWeeks(input, 11, 8, 6, 4);
        setPercentages(input, 25, 30, 40, 5);
        input.onsiteStartDate = Date.newInstance(2025, 3, 1);
        input.onsiteEndDate = Date.newInstance(2025, 3, 14);

        List<ScheduleHoursDistributor.ScheduleExceptionOutputWrapper> result = run(input);

        System.assertNotEquals(null, result, 'Result should not be null');
        System.assertEquals(1, result.size(), 'Only one result should be returned');
        System.assertEquals(null, result[0].errorMessage, 'There should be no error messages');
        System.assert(result[0].scheduleExceptions.size() > 0, 'Schedule exceptions should be generated');
        for (pse__Schedule_Exception__c exc : result[0].scheduleExceptions) {
            System.assertEquals(schedule.Id, exc.pse__Schedule__c, 'Every exception must reference the input schedule');
        }
    }

    @isTest
    static void testGenerateScheduleExceptionsWithNullScheduleId() {
        ScheduleHoursDistributor.ScheduleInput input = buildInput(null, Date.newInstance(2025, 1, 1), Date.newInstance(2025, 7, 1), 200);
        setWeeks(input, 11, 8, 6, 4);
        setPercentages(input, 25, 30, 40, 5);
        input.onsiteStartDate = Date.newInstance(2025, 3, 1);
        input.onsiteEndDate = Date.newInstance(2025, 3, 14);

        List<ScheduleHoursDistributor.ScheduleExceptionOutputWrapper> result = run(input);

        System.assertEquals(1, result.size(), 'Only one result should be returned');
        System.assertEquals(0, result[0].scheduleExceptions.size(), 'No schedule exceptions should be generated');
        System.assertEquals('Error: Schedule ID cannot be null.', result[0].errorMessage, 'Error message should match expected output');
    }

    @isTest
    static void testStartDateAfterEndDateValidation() {
        ScheduleHoursDistributor.ScheduleInput input = buildInput(schedule2025Id(), Date.newInstance(2025, 7, 2), Date.newInstance(2025, 7, 1), 100);
        setWeeks(input, 1, 1, 1, 1);
        setPercentages(input, 25, 25, 25, 25);

        List<ScheduleHoursDistributor.ScheduleExceptionOutputWrapper> result = run(input);
        System.assertEquals(1, result.size());
        System.assertEquals('Error: Start Date must be on or before End Date.', result[0].errorMessage);
    }

    @isTest
    static void testOnsiteStartAfterEndDateValidation() {
        ScheduleHoursDistributor.ScheduleInput input = buildInput(schedule2025Id(), Date.newInstance(2025, 1, 1), Date.newInstance(2025, 7, 1), 100);
        setWeeks(input, 1, 1, 1, 1);
        setPercentages(input, 25, 25, 25, 25);
        input.onsiteStartDate = Date.newInstance(2025, 4, 10);
        input.onsiteEndDate = Date.newInstance(2025, 4, 5);

        List<ScheduleHoursDistributor.ScheduleExceptionOutputWrapper> result = run(input);
        System.assertEquals(1, result.size());
        System.assertEquals('Error: Onsite Start Date must be on or before Onsite End Date.', result[0].errorMessage);
    }

    @isTest
    static void testNegativeNumberOfHours_ReturnsError() {
        ScheduleHoursDistributor.ScheduleInput input = buildInput(schedule2025Id(), Date.newInstance(2025, 1, 1), Date.newInstance(2025, 7, 1), -100);
        setWeeks(input, 1, 1, 1, 1);
        setPercentages(input, 25, 25, 25, 25);

        List<ScheduleHoursDistributor.ScheduleExceptionOutputWrapper> result = run(input);
        System.assertEquals(1, result.size());
        System.assertEquals('Error: Number of Hours must be greater than zero.', result[0].errorMessage);
    }

    @isTest
    static void testNegativeCatWeeks_ReturnsError() {
        ScheduleHoursDistributor.ScheduleInput input = buildInput(schedule2025Id(), Date.newInstance(2025, 1, 1), Date.newInstance(2025, 7, 1), 100);
        setWeeks(input, -2, 1, 1, 1);
        setPercentages(input, 25, 25, 25, 25);

        List<ScheduleHoursDistributor.ScheduleExceptionOutputWrapper> result = run(input);
        System.assertEquals(1, result.size());
        System.assertEquals('Error: Week values cannot be negative.', result[0].errorMessage);
    }

    @isTest
    static void testNegativePercentages_ReturnsError() {
        ScheduleHoursDistributor.ScheduleInput input = buildInput(schedule2025Id(), Date.newInstance(2025, 1, 1), Date.newInstance(2025, 7, 1), 100);
        setWeeks(input, 1, 1, 1, 1);
        setPercentages(input, -10, 25, 25, 25);

        List<ScheduleHoursDistributor.ScheduleExceptionOutputWrapper> result = run(input);
        System.assertEquals(1, result.size());
        System.assertEquals('Error: Percentage values cannot be negative.', result[0].errorMessage);
    }

    // ---------------------------------------------------------------------
    // Holidays / onsite gap / post
    // ---------------------------------------------------------------------

    @isTest
    static void testExistingMultiDayExceptionExcludesHolidayDates() {
        // Select the multi-day holiday explicitly (2025-03-10 .. 2025-03-12)
        pse__Schedule_Exception__c holiday = [
            SELECT Id, pse__Date__c, pse__End_Date__c
            FROM pse__Schedule_Exception__c
            WHERE pse__Date__c = :Date.newInstance(2025, 3, 10)
            LIMIT 1
        ];
        System.assert(holiday.pse__End_Date__c > holiday.pse__Date__c, 'Fixture must be a multi-day holiday');

        ScheduleHoursDistributor.ScheduleInput input = buildInput(schedule2025Id(), Date.newInstance(2025, 1, 1), Date.newInstance(2025, 7, 1), 200);
        setWeeks(input, 11, 8, 6, 4);
        setPercentages(input, 25, 30, 40, 5);
        // Onsite gap week = 2025-02-24 .. 2025-03-02, so Post = 2025-03-03 .. 2025-03-30 and contains the holiday.
        input.onsiteStartDate = Date.newInstance(2025, 3, 1);
        input.onsiteEndDate = Date.newInstance(2025, 3, 14);
        input.existingExceptions = new List<pse__Schedule_Exception__c>{ holiday };

        List<ScheduleHoursDistributor.ScheduleExceptionOutputWrapper> result = run(input);
        System.assertEquals(1, result.size());
        System.assertEquals(null, result[0].errorMessage);

        Boolean foundSegmentEndingBeforeHoliday = false;
        Boolean foundSegmentStartingAfterHoliday = false;
        for (pse__Schedule_Exception__c exc : result[0].scheduleExceptions) {
            Date s = exc.pse__Date__c;
            Date e = endOf(exc);
            System.assertEquals(false, (s <= holiday.pse__End_Date__c && e >= holiday.pse__Date__c), 'Generated exception should not overlap holiday range: ' + s + ' - ' + e);
            if (e == Date.newInstance(2025, 3, 9)) foundSegmentEndingBeforeHoliday = true;
            if (s == Date.newInstance(2025, 3, 13)) foundSegmentStartingAfterHoliday = true;
        }
        System.assert(foundSegmentEndingBeforeHoliday, 'Post category should be split so a segment ends the day before the holiday (2025-03-09)');
        System.assert(foundSegmentStartingAfterHoliday, 'Post category should resume the day after the holiday (2025-03-13)');
    }

    @isTest
    static void testOnsiteGapWeekIsSevenDaysZeroHours() {
        ScheduleHoursDistributor.ScheduleInput input = buildInput(schedule2025Id(), Date.newInstance(2025, 1, 1), Date.newInstance(2025, 7, 1), 200);
        setWeeks(input, 11, 8, 6, 4);
        setPercentages(input, 25, 30, 40, 5);
        // Choose an onsite start mid-week to exercise week-start calculation
        input.onsiteStartDate = Date.newInstance(2025, 3, 5);
        input.onsiteEndDate = Date.newInstance(2025, 3, 10);

        List<ScheduleHoursDistributor.ScheduleExceptionOutputWrapper> result = run(input);
        System.assertEquals(1, result.size());
        System.assertEquals(null, result[0].errorMessage);

        // The Monday of the week containing onsiteStartDate (2025-03-05 Wed) must be 2025-03-03.
        Date expectedGapStart = Date.newInstance(2025, 3, 3);
        Date expectedGapEnd = Date.newInstance(2025, 3, 9);
        pse__Schedule_Exception__c gapExc = null;
        for (pse__Schedule_Exception__c exc : result[0].scheduleExceptions) {
            if (exc.pse__Date__c == expectedGapStart) {
                gapExc = exc;
                break;
            }
        }
        System.assertNotEquals(null, gapExc, 'Onsite gap exception must start on the Monday of the onsite start week (2025-03-03)');
        System.assertEquals(expectedGapEnd, gapExc.pse__End_Date__c, 'Onsite gap exception must end on Sunday of the onsite start week (2025-03-09)');
        System.assertEquals(0, gapExc.pse__Monday_Hours__c, 'Onsite gap Monday hours must be zero');
        System.assertEquals(0, gapExc.pse__Tuesday_Hours__c, 'Onsite gap Tuesday hours must be zero');
        System.assertEquals(0, gapExc.pse__Wednesday_Hours__c, 'Onsite gap Wednesday hours must be zero');
        System.assertEquals(0, gapExc.pse__Thursday_Hours__c, 'Onsite gap Thursday hours must be zero');
        System.assertEquals(0, gapExc.pse__Friday_Hours__c, 'Onsite gap Friday hours must be zero');
        System.assertEquals(0, gapExc.pse__Saturday_Hours__c, 'Onsite gap Saturday hours must be zero');
        System.assertEquals(0, gapExc.pse__Sunday_Hours__c, 'Onsite gap Sunday hours must be zero');
    }

    @isTest
    static void testOnsiteGapClampedToInputDateRange() {
        pse__Schedule__c schedule = new pse__Schedule__c(
            pse__Start_Date__c = Date.newInstance(2026, 6, 1),
            pse__End_Date__c = Date.newInstance(2026, 10, 10),
            pse__Scheduled_Hours__c = 20,
            pse__Monday_Hours__c = 8,
            pse__Tuesday_Hours__c = 8,
            pse__Wednesday_Hours__c = 8,
            pse__Thursday_Hours__c = 8,
            pse__Friday_Hours__c = 8,
            pse__Saturday_Hours__c = 0,
            pse__Sunday_Hours__c = 0
        );
        insert schedule;

        ScheduleHoursDistributor.ScheduleInput input = buildInput(schedule.Id, Date.newInstance(2026, 6, 1), Date.newInstance(2026, 10, 10), 20);
        setWeeks(input, 10, 4, 6, 6);
        setPercentages(input, 20, 20, 50, 10);
        input.onsiteStartDate = Date.newInstance(2026, 10, 5);
        input.onsiteEndDate = Date.newInstance(2026, 10, 8);
        input.existingExceptions = new List<pse__Schedule_Exception__c>{
            zeroHourException(schedule.Id, Date.newInstance(2026, 6, 19), Date.newInstance(2026, 6, 19)),
            zeroHourException(schedule.Id, Date.newInstance(2026, 7, 2), Date.newInstance(2026, 7, 2)),
            zeroHourException(schedule.Id, Date.newInstance(2026, 7, 3), Date.newInstance(2026, 7, 3)),
            zeroHourException(schedule.Id, Date.newInstance(2026, 9, 4), Date.newInstance(2026, 9, 4)),
            zeroHourException(schedule.Id, Date.newInstance(2026, 9, 7), Date.newInstance(2026, 9, 7))
        };

        List<ScheduleHoursDistributor.ScheduleExceptionOutputWrapper> result = run(input);

        System.assertEquals(1, result.size(), 'Should return one result');
        System.assertEquals(null, result[0].errorMessage, 'Should not return an error');

        Boolean foundOnsiteGap = false;
        for (pse__Schedule_Exception__c exc : result[0].scheduleExceptions) {
            System.assert(exc.pse__Date__c >= input.startDate, 'Generated exception starts before the input start date');
            System.assert(endOf(exc) <= input.endDate, 'Generated exception ends after the input end date');
            if (exc.pse__Date__c == Date.newInstance(2026, 10, 5) && endOf(exc) == Date.newInstance(2026, 10, 10)) {
                foundOnsiteGap = true;
            }
        }
        System.assertEquals(true, foundOnsiteGap, 'Onsite gap should be clamped to end on 2026-10-10');
    }

    @isTest
    static void testPostWeeksConstrainsPostDateRange() {
        ScheduleHoursDistributor.ScheduleInput input = buildInput(schedule2025Id(), Date.newInstance(2025, 1, 1), Date.newInstance(2025, 4, 30), 120);
        setWeeks(input, 4, 3, 2, 2); // Post should be exactly 14 days from the day after onsite gap week.
        setPercentages(input, 25, 25, 25, 25);
        input.onsiteStartDate = Date.newInstance(2025, 2, 3); // Monday
        input.onsiteEndDate = Date.newInstance(2025, 2, 10);

        List<ScheduleHoursDistributor.ScheduleExceptionOutputWrapper> result = run(input);

        System.assertEquals(1, result.size(), 'Should return one result');
        System.assertEquals(null, result[0].errorMessage, 'Should not return an error');

        Date expectedPostStart = Date.newInstance(2025, 2, 10);
        Date expectedPostEnd = Date.newInstance(2025, 2, 23);

        Boolean foundPostStart = false;
        Boolean foundPostEnd = false;
        Boolean foundAfterPostEnd = false;
        for (pse__Schedule_Exception__c exc : result[0].scheduleExceptions) {
            Date s = exc.pse__Date__c;
            Date e = endOf(exc);
            if (s == expectedPostStart) foundPostStart = true;
            if (e == expectedPostEnd) foundPostEnd = true;
            if (s > expectedPostEnd || e > expectedPostEnd) foundAfterPostEnd = true;
        }

        System.assertEquals(true, foundPostStart, 'Post category must start exactly on 2025-02-10 (day after onsite gap week ends)');
        System.assertEquals(true, foundPostEnd, 'Post category must end exactly on 2025-02-23 (postWeeks × 7 days = 14 days from post start)');
        System.assertEquals(false, foundAfterPostEnd, 'No generated exception should extend beyond the postWeeks-derived end date');
    }

    @isTest
    static void testGetNormalizedDayOfWeek_MondayIsOne() {
        System.assertEquals(1, ScheduleHoursDistributor.getNormalizedDayOfWeek(Date.newInstance(2025, 3, 3)), 'Monday should be 1');
        System.assertEquals(2, ScheduleHoursDistributor.getNormalizedDayOfWeek(Date.newInstance(2025, 3, 4)), 'Tuesday should be 2');
        System.assertEquals(3, ScheduleHoursDistributor.getNormalizedDayOfWeek(Date.newInstance(2025, 3, 5)), 'Wednesday should be 3');
        System.assertEquals(4, ScheduleHoursDistributor.getNormalizedDayOfWeek(Date.newInstance(2025, 3, 6)), 'Thursday should be 4');
        System.assertEquals(5, ScheduleHoursDistributor.getNormalizedDayOfWeek(Date.newInstance(2025, 3, 7)), 'Friday should be 5');
        System.assertEquals(6, ScheduleHoursDistributor.getNormalizedDayOfWeek(Date.newInstance(2025, 3, 8)), 'Saturday should be 6');
        System.assertEquals(7, ScheduleHoursDistributor.getNormalizedDayOfWeek(Date.newInstance(2025, 3, 9)), 'Sunday should be 7');
    }

    // ---------------------------------------------------------------------
    // Hour math
    // ---------------------------------------------------------------------

    @isTest
    static void testPercentSumLessAndGreaterThan100() {
        // Cat1 = 2025-01-11..2025-02-07 (20 weekdays), Cat2 = 2025-02-08..2025-03-07 (20 weekdays); Cat3/Post invalid.
        Date cat1RangeStart = Date.newInstance(2025, 1, 11);
        Date cat1RangeEnd = Date.newInstance(2025, 2, 7);
        Date cat2RangeStart = Date.newInstance(2025, 2, 8);
        Date cat2RangeEnd = Date.newInstance(2025, 3, 7);

        // Sum < 100: 30 + 20 = 50 -> missing 50 split evenly -> 55 / 45
        ScheduleHoursDistributor.ScheduleInput under = buildInput(schedule2025Id(), Date.newInstance(2025, 1, 6), Date.newInstance(2025, 3, 7), 100);
        setWeeks(under, 4, 4, 0, 0);
        setPercentages(under, 30, 20, 10, 10); // cat3/post percentages are ignored because those categories are invalid
        List<ScheduleHoursDistributor.ScheduleExceptionOutputWrapper> r1 = run(under);
        System.assertEquals(null, r1[0].errorMessage);
        System.assertEquals(55, sumScheduledHours(r1[0].scheduleExceptions, cat1RangeStart, cat1RangeEnd), 'Cat1 should be normalized to 55%');
        System.assertEquals(45, sumScheduledHours(r1[0].scheduleExceptions, cat2RangeStart, cat2RangeEnd), 'Cat2 should be normalized to 45%');

        // Sum > 100: 90 + 30 = 120 -> excess 20 removed evenly -> 80 / 20
        ScheduleHoursDistributor.ScheduleInput over = buildInput(schedule2025Id(), Date.newInstance(2025, 1, 6), Date.newInstance(2025, 3, 7), 100);
        setWeeks(over, 4, 4, 0, 0);
        setPercentages(over, 90, 30, 10, 10);
        List<ScheduleHoursDistributor.ScheduleExceptionOutputWrapper> r2 = run(over);
        System.assertEquals(null, r2[0].errorMessage);
        System.assertEquals(80, sumScheduledHours(r2[0].scheduleExceptions, cat1RangeStart, cat1RangeEnd), 'Cat1 should be normalized to 80%');
        System.assertEquals(20, sumScheduledHours(r2[0].scheduleExceptions, cat2RangeStart, cat2RangeEnd), 'Cat2 should be normalized to 20%');
    }

    @isTest
    static void testMathWithoutExistingExceptions_TotalHoursMatch() {
        // Single Mon-Fri week (2025-01-06 .. 2025-01-10); only Cat1 is valid -> 50h / 5 days = 10.00h per day
        ScheduleHoursDistributor.ScheduleInput input = buildInput(schedule2025Id(), Date.newInstance(2025, 1, 6), Date.newInstance(2025, 1, 10), 50);
        setWeeks(input, 1, 0, 0, 0);
        setPercentages(input, 60, 20, 15, 5);

        List<ScheduleHoursDistributor.ScheduleExceptionOutputWrapper> result = run(input);
        System.assertEquals(1, result.size());
        System.assertEquals(null, result[0].errorMessage);
        System.assertEquals(1, result[0].scheduleExceptions.size(), 'One uninterrupted segment expected');
        System.assertEquals(10, result[0].scheduleExceptions[0].pse__Monday_Hours__c, 'Expected 10 hours per day');
        System.assertEquals(50, sumScheduledHours(result[0].scheduleExceptions), 'All requested hours should be scheduled');
    }

    @isTest
    static void testMathWithExistingHolidayExcludesDate_TotalHoursMatch() {
        // Use the single-day holiday inserted in @testSetup (2025-01-08, Wednesday)
        pse__Schedule_Exception__c holiday = [
            SELECT Id, pse__Date__c, pse__End_Date__c
            FROM pse__Schedule_Exception__c
            WHERE pse__Date__c = :Date.newInstance(2025, 1, 8)
            LIMIT 1
        ];

        // 4 usable days -> 50h / 4 = 12.50h per day
        ScheduleHoursDistributor.ScheduleInput input = buildInput(schedule2025Id(), Date.newInstance(2025, 1, 6), Date.newInstance(2025, 1, 10), 50);
        setWeeks(input, 1, 0, 0, 0);
        setPercentages(input, 60, 20, 15, 5);
        input.existingExceptions = new List<pse__Schedule_Exception__c>{ holiday };

        List<ScheduleHoursDistributor.ScheduleExceptionOutputWrapper> result = run(input);
        System.assertEquals(1, result.size());
        System.assertEquals(null, result[0].errorMessage);

        Date hol = holiday.pse__Date__c;
        for (pse__Schedule_Exception__c exc : result[0].scheduleExceptions) {
            System.assertEquals(false, (exc.pse__Date__c <= hol && endOf(exc) >= hol), 'Generated exceptions must not include holiday date');
        }
        System.assertEquals(2, result[0].scheduleExceptions.size(), 'Range should be split around the holiday');
        System.assertEquals(50, sumScheduledHours(result[0].scheduleExceptions), 'All requested hours should land on the 4 remaining days');
    }

    @isTest
    static void testPerCategoryHoursMatchConfiguredPercentages() {
        ScheduleHoursDistributor.ScheduleInput input = buildInput(schedule2025Id(), Date.newInstance(2025, 1, 6), Date.newInstance(2025, 3, 7), 100);
        setWeeks(input, 4, 4, 0, 0);
        setPercentages(input, 60, 40, 0, 0);

        List<ScheduleHoursDistributor.ScheduleExceptionOutputWrapper> result = run(input);
        System.assertEquals(1, result.size());
        System.assertEquals(null, result[0].errorMessage, 'Should not return an error');

        // Known category date boundaries derived from class logic (4 weeks × 7 = 28 days each,
        // working backward from endDate with cat3 invalid at 0 weeks):
        Decimal cat1Hours = sumScheduledHours(result[0].scheduleExceptions, Date.newInstance(2025, 1, 11), Date.newInstance(2025, 2, 7));
        Decimal cat2Hours = sumScheduledHours(result[0].scheduleExceptions, Date.newInstance(2025, 2, 8), Date.newInstance(2025, 3, 7));

        // Per-day: 60/20 = 3.00, 40/20 = 2.00 — both divide evenly so no rounding error.
        System.assertEquals(60, cat1Hours, 'Cat1 should receive exactly 60 hours (60% of 100)');
        System.assertEquals(40, cat2Hours, 'Cat2 should receive exactly 40 hours (40% of 100)');
    }

    @isTest
    static void testCapacityCapAndOverflowDropped_NoError() {
        // 300h requested over 5 weekdays; capacity is 5 × 24 = 120h
        ScheduleHoursDistributor.ScheduleInput input = buildInput(schedule2025Id(), Date.newInstance(2025, 1, 6), Date.newInstance(2025, 1, 10), 300);
        setWeeks(input, 1, 0, 0, 0);
        setPercentages(input, 100, 0, 0, 0);

        List<ScheduleHoursDistributor.ScheduleExceptionOutputWrapper> result = run(input);

        System.assertEquals(1, result.size(), 'Should return one wrapper');
        System.assertEquals(null, result[0].errorMessage, 'Overflow should not produce an error');
        System.assert(result[0].scheduleExceptions.size() > 0, 'Should still create schedule exceptions');

        for (pse__Schedule_Exception__c exc : result[0].scheduleExceptions) {
            for (Date d = exc.pse__Date__c; d <= endOf(exc); d = d.addDays(1)) {
                System.assert(hoursOnDate(exc, d) <= 24, 'No scheduled day should exceed 24 hours');
            }
        }
        System.assertEquals(120, sumScheduledHours(result[0].scheduleExceptions), 'Five-day range should be filled to exactly 120 hours; the rest is dropped');
    }

    // ---------------------------------------------------------------------
    // Public helpers
    // ---------------------------------------------------------------------

    @isTest
    static void testExtractHolidayDates_NullAndRanges() {
        List<pse__Schedule_Exception__c> listWithNull = new List<pse__Schedule_Exception__c>();
        listWithNull.add(null);
        listWithNull.add(new pse__Schedule_Exception__c(pse__Date__c = Date.newInstance(2025, 4, 1), pse__End_Date__c = null));
        listWithNull.add(new pse__Schedule_Exception__c(pse__Date__c = Date.newInstance(2025, 4, 10), pse__End_Date__c = Date.newInstance(2025, 4, 12)));

        Set<Date> holidays = ScheduleHoursDistributor.extractHolidayDates(listWithNull);
        System.assertEquals(true, holidays.contains(Date.newInstance(2025, 4, 1)));
        System.assertEquals(true, holidays.contains(Date.newInstance(2025, 4, 10)));
        System.assertEquals(true, holidays.contains(Date.newInstance(2025, 4, 11)));
        System.assertEquals(true, holidays.contains(Date.newInstance(2025, 4, 12)));
        System.assertEquals(4, holidays.size(), 'Should include all dates from single and multi-day exceptions');

        System.assertEquals(0, ScheduleHoursDistributor.extractHolidayDates(null).size(), 'Null input should return empty set');
    }

    @isTest
    static void testAddSplitExceptions_SplittingBehavior() {
        Id scheduleId = schedule2025Id();

        // 1) segStart is a split -> first segment should start at next day
        Date segStart = Date.newInstance(2025, 1, 6);
        Date segEnd = Date.newInstance(2025, 1, 10);
        Set<Date> splits = new Set<Date>{ Date.newInstance(2025, 1, 6) };
        List<pse__Schedule_Exception__c> allEx = new List<pse__Schedule_Exception__c>();
        List<pse__Schedule_Exception__c> cat = new List<pse__Schedule_Exception__c>();
        ScheduleHoursDistributor.addSplitExceptions(segStart, segEnd, 8, 5, scheduleId, segStart, segEnd, splits, allEx, cat);
        System.assertEquals(1, cat.size(), 'Should create exactly one segment after the initial split day');
        System.assertEquals(Date.newInstance(2025, 1, 7), cat[0].pse__Date__c, 'First segment should start at 2025-01-07');
        System.assertEquals(Date.newInstance(2025, 1, 10), cat[0].pse__End_Date__c, 'First segment should end at 2025-01-10');

        // 2) all days are splits -> no exceptions created
        splits = new Set<Date>();
        for (Date d = segStart; d <= segEnd; d = d.addDays(1)) splits.add(d);
        allEx.clear();
        cat.clear();
        ScheduleHoursDistributor.addSplitExceptions(segStart, segEnd, 8, 5, scheduleId, segStart, segEnd, splits, allEx, cat);
        System.assertEquals(0, cat.size(), 'When all days are splits, no exceptions should be created');

        // 3) multiple split days produce multiple exceptions
        segStart = Date.newInstance(2025, 1, 6);
        segEnd = Date.newInstance(2025, 1, 20);
        splits = new Set<Date>{ Date.newInstance(2025, 1, 10), Date.newInstance(2025, 1, 15) };
        allEx.clear();
        cat.clear();
        ScheduleHoursDistributor.addSplitExceptions(segStart, segEnd, 8, 5, scheduleId, segStart, segEnd, splits, allEx, cat);
        System.assertEquals(3, cat.size(), 'Should produce three split segments for two split days');
        System.assertEquals(3, allEx.size(), 'Segments should also be added to the combined list');
        System.assertEquals(Date.newInstance(2025, 1, 6), cat[0].pse__Date__c, 'Segment 1 should start at 2025-01-06');
        System.assertEquals(Date.newInstance(2025, 1, 9), cat[0].pse__End_Date__c, 'Segment 1 should end at 2025-01-09');
        System.assertEquals(Date.newInstance(2025, 1, 11), cat[1].pse__Date__c, 'Segment 2 should start at 2025-01-11');
        System.assertEquals(Date.newInstance(2025, 1, 14), cat[1].pse__End_Date__c, 'Segment 2 should end at 2025-01-14');
        System.assertEquals(Date.newInstance(2025, 1, 16), cat[2].pse__Date__c, 'Segment 3 should start at 2025-01-16');
        System.assertEquals(Date.newInstance(2025, 1, 20), cat[2].pse__End_Date__c, 'Segment 3 should end at 2025-01-20');
    }

    @isTest
    static void testCountUsableWorkdays_VariousRanges() {
        Date monday = Date.newInstance(2025, 1, 6);
        Date friday = Date.newInstance(2025, 1, 10);
        Date sunday = Date.newInstance(2025, 1, 12);

        // Default overload (Mon-Fri)
        System.assertEquals(5, ScheduleHoursDistributor.countUsableWorkdays(monday, friday, new Set<Date>()), 'Mon-Fri week has 5 workdays');
        System.assertEquals(4, ScheduleHoursDistributor.countUsableWorkdays(monday, friday, new Set<Date>{ Date.newInstance(2025, 1, 8) }), 'Holiday on Wednesday leaves 4');
        System.assertEquals(1, ScheduleHoursDistributor.countUsableWorkdays(friday, sunday, new Set<Date>()), 'Fri-Sun has only Friday');

        Set<Date> exclAll = new Set<Date>();
        for (Date d = monday; d <= friday; d = d.addDays(1)) exclAll.add(d);
        System.assertEquals(0, ScheduleHoursDistributor.countUsableWorkdays(monday, friday, exclAll), 'All weekdays excluded leaves 0');

        // Explicit workday patterns over a full Mon-Sun week
        System.assertEquals(6, ScheduleHoursDistributor.countUsableWorkdays(monday, sunday, new Set<Date>(), 6), '6-day schedule should count Mon-Sat');
        System.assertEquals(7, ScheduleHoursDistributor.countUsableWorkdays(monday, sunday, new Set<Date>(), 7), '7-day schedule should count Mon-Sun');
        System.assertEquals(3, ScheduleHoursDistributor.countUsableWorkdays(monday, sunday, new Set<Date>(), 3), '3-day schedule should count Mon-Wed');

        // Exclusions still apply in weekend-enabled mode (2025-01-11 is a Saturday)
        System.assertEquals(6, ScheduleHoursDistributor.countUsableWorkdays(monday, sunday, new Set<Date>{ Date.newInstance(2025, 1, 11) }, 7), 'Excluded dates should be removed even in 7-day mode');
    }

    @isTest
    static void testNumberOfWorkDaysOutOfRange_IsConsistentEverywhere() {
        Date weekStart = Date.newInstance(2025, 1, 6); // Monday
        Date weekEnd = Date.newInstance(2025, 1, 12); // Sunday

        // Low out-of-range value should clamp to 1 (Monday only).
        System.assertEquals(1, ScheduleHoursDistributor.countUsableWorkdays(weekStart, weekEnd, new Set<Date>(), 0), 'numberOfWorkDays=0 should clamp to 1 usable day');
        pse__Schedule_Exception__c excLow = ScheduleHoursDistributor.createScheduleException(null, weekStart, weekEnd, 0, 8);
        System.assertEquals(8, excLow.pse__Monday_Hours__c, 'Clamped low value should populate Monday hours');
        System.assertEquals(0, excLow.pse__Tuesday_Hours__c, 'Clamped low value should not populate Tuesday hours');
        System.assertEquals(0, excLow.pse__Sunday_Hours__c, 'Clamped low value should not populate Sunday hours');

        // High out-of-range value should clamp to 7 (all days).
        System.assertEquals(7, ScheduleHoursDistributor.countUsableWorkdays(weekStart, weekEnd, new Set<Date>(), 9), 'numberOfWorkDays=9 should clamp to 7 usable days');
        pse__Schedule_Exception__c excHigh = ScheduleHoursDistributor.createScheduleException(null, weekStart, weekEnd, 9, 8);
        System.assertEquals(8, excHigh.pse__Monday_Hours__c, 'Clamped high value should populate Monday hours');
        System.assertEquals(8, excHigh.pse__Tuesday_Hours__c, 'Clamped high value should populate Tuesday hours');
        System.assertEquals(8, excHigh.pse__Sunday_Hours__c, 'Clamped high value should populate Sunday hours');
    }

    // ---------------------------------------------------------------------
    // Bulk / batch
    // ---------------------------------------------------------------------

    @isTest
    static void testAllCategoriesInvalid_NoCrash() {
        ScheduleHoursDistributor.ScheduleInput input = buildInput(schedule2025Id(), Date.newInstance(2025, 1, 1), Date.newInstance(2025, 1, 10), 40);
        setWeeks(input, 0, 0, 0, 0); // zero weeks -> every category invalid
        setPercentages(input, 25, 25, 25, 25);

        List<ScheduleHoursDistributor.ScheduleExceptionOutputWrapper> result = run(input);
        System.assertEquals(1, result.size());
        System.assertEquals(null, result[0].errorMessage);
        System.assertEquals(0, result[0].scheduleExceptions.size(), 'No categories valid -> expect zero generated exceptions');
    }

    @isTest
    static void testGenerateScheduleExceptions_MultipleValidInputs() {
        List<pse__Schedule__c> schedules = [SELECT Id, pse__Start_Date__c, pse__End_Date__c, pse__Scheduled_Hours__c FROM pse__Schedule__c ORDER BY pse__Start_Date__c LIMIT 2];
        System.assertEquals(2, schedules.size(), 'Expect two schedules from setup');

        List<ScheduleHoursDistributor.ScheduleInput> inputs = new List<ScheduleHoursDistributor.ScheduleInput>();
        for (pse__Schedule__c sched : schedules) {
            ScheduleHoursDistributor.ScheduleInput input = buildInput(sched.Id, sched.pse__Start_Date__c, sched.pse__End_Date__c, sched.pse__Scheduled_Hours__c);
            setWeeks(input, 4, 4, 4, 4);
            setPercentages(input, 25, 25, 25, 25);
            input.onsiteStartDate = sched.pse__Start_Date__c.addMonths(1);
            input.onsiteEndDate = sched.pse__Start_Date__c.addMonths(1).addDays(6);
            inputs.add(input);
        }

        List<ScheduleHoursDistributor.ScheduleExceptionOutputWrapper> results = ScheduleHoursDistributor.generateCategoryScheduleExceptions(inputs);
        System.assertEquals(2, results.size(), 'Should return one wrapper per input');
        for (Integer i = 0; i < results.size(); i++) {
            System.assertEquals(null, results[i].errorMessage, 'Input ' + i + ' should not have an error');
            System.assert(results[i].scheduleExceptions.size() > 0, 'Input ' + i + ' should generate exceptions');
            for (pse__Schedule_Exception__c exc : results[i].scheduleExceptions) {
                System.assertEquals(schedules[i].Id, exc.pse__Schedule__c, 'Output ' + i + ' must only contain exceptions for its own schedule');
            }
        }
    }

    @isTest
    static void testGenerateScheduleExceptions_MixedValidAndInvalidInputs() {
        pse__Schedule__c schedule = [SELECT Id, pse__Start_Date__c, pse__End_Date__c, pse__Scheduled_Hours__c FROM pse__Schedule__c WHERE pse__Start_Date__c = :Date.newInstance(2025, 1, 1) LIMIT 1];

        ScheduleHoursDistributor.ScheduleInput validInput = buildInput(schedule.Id, schedule.pse__Start_Date__c, schedule.pse__End_Date__c, schedule.pse__Scheduled_Hours__c);
        setWeeks(validInput, 4, 4, 4, 4);
        setPercentages(validInput, 25, 25, 25, 25);

        ScheduleHoursDistributor.ScheduleInput invalidInput = buildInput(null, Date.newInstance(2025, 1, 1), Date.newInstance(2025, 7, 1), 100);
        setWeeks(invalidInput, 1, 1, 1, 1);
        setPercentages(invalidInput, 25, 25, 25, 25);

        List<ScheduleHoursDistributor.ScheduleExceptionOutputWrapper> results = ScheduleHoursDistributor.generateCategoryScheduleExceptions(
            new List<ScheduleHoursDistributor.ScheduleInput>{ validInput, invalidInput }
        );
        System.assertEquals(2, results.size(), 'Should return two wrappers for two inputs');
        System.assertEquals(null, results[0].errorMessage, 'Valid input should not have an error');
        System.assert(results[0].scheduleExceptions.size() > 0, 'Valid input should generate exceptions');
        System.assertEquals('Error: Schedule ID cannot be null.', results[1].errorMessage, 'Error message should match expected');
        System.assertEquals(0, results[1].scheduleExceptions.size(), 'Invalid input should generate no exceptions');
    }

    @isTest
    static void testGenerateScheduleExceptions_TwoValidInputs_NoErrors() {
        List<pse__Schedule__c> schedules = [SELECT Id, pse__Start_Date__c, pse__End_Date__c, pse__Scheduled_Hours__c FROM pse__Schedule__c ORDER BY pse__Start_Date__c LIMIT 2];
        System.assertEquals(2, schedules.size(), 'Expect two schedules from setup');

        List<ScheduleHoursDistributor.ScheduleInput> inputs = new List<ScheduleHoursDistributor.ScheduleInput>();
        for (pse__Schedule__c sched : schedules) {
            ScheduleHoursDistributor.ScheduleInput input = buildInput(sched.Id, sched.pse__Start_Date__c, sched.pse__End_Date__c, sched.pse__Scheduled_Hours__c);
            setWeeks(input, 4, 4, 4, 4);
            setPercentages(input, 25, 25, 25, 25);
            inputs.add(input);
        }

        List<ScheduleHoursDistributor.ScheduleExceptionOutputWrapper> results = ScheduleHoursDistributor.generateCategoryScheduleExceptions(inputs);

        System.assertEquals(2, results.size(), 'Should return two wrappers');
        for (Integer i = 0; i < results.size(); i++) {
            System.assertEquals(null, results[i].errorMessage, 'Input ' + i + ' should have no error');
            System.assert(results[i].scheduleExceptions.size() > 0, 'Input ' + i + ' should generate exceptions');
            for (pse__Schedule_Exception__c exc : results[i].scheduleExceptions) {
                System.assert(exc.pse__Date__c >= inputs[i].startDate && endOf(exc) <= inputs[i].endDate, 'Exceptions must stay inside the input range');
            }
        }
    }
}
