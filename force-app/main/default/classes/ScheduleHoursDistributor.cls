public with sharing class ScheduleHoursDistributor {

    @InvocableMethod(label='Generate Category Schedule Exceptions' description='Generates schedule exception records for a category, skipping holidays.')
    public static List<ScheduleExceptionOutputWrapper> generateCategoryScheduleExceptions(List<ScheduleInput> inputList) {
        List<ScheduleExceptionOutputWrapper> outputList = new List<ScheduleExceptionOutputWrapper>();
        try {
            if (inputList == null || inputList.isEmpty()) {
                return new List<ScheduleExceptionOutputWrapper>();
            }
            ScheduleInput input = inputList[0];

            // Input validation
            if (input.scheduleId == null) return returnErrorWrapper('Error: Schedule ID cannot be null.');
            if (input.startDate == null) return returnErrorWrapper('Error: Start Date cannot be null.');
            if (input.endDate == null) return returnErrorWrapper('Error: End Date cannot be null.');
            if (input.startDate > input.endDate) return returnErrorWrapper('Error: Start Date must be on or before End Date.');
            if (input.numberOfHours == null) return returnErrorWrapper('Error: Number of Hours cannot be null.');
            if (input.numberOfWorkDays == null) return returnErrorWrapper('Error: Number of Work Days cannot be null.');
            if (input.cat1Weeks == null || input.cat2Weeks == null || input.cat3Weeks == null || input.postWeeks == null)
                return returnErrorWrapper('Error: Week values cannot be null.');
            if (input.cat1Percentage == null || input.cat2Percentage == null || input.cat3Percentage == null || input.postPercentage == null)
                return returnErrorWrapper('Error: Percentage values cannot be null.');
            if ((input.onsiteStartDate != null && input.onsiteEndDate == null) || (input.onsiteStartDate == null && input.onsiteEndDate != null))
                return returnErrorWrapper('Error: Both Onsite Start Date and Onsite End Date must be provided.');
            if (input.onsiteStartDate != null && input.onsiteEndDate != null && input.onsiteStartDate > input.onsiteEndDate)
                return returnErrorWrapper('Error: Onsite Start Date must be on or before Onsite End Date.');

            // 1. Calculate holidays
            Set<Date> holidayDates = extractHolidayDates(input.existingExceptions);

            // 2. Onsite needed check
            Boolean onsiteNeeded = false;
            if (input.onsiteStartDate != null && input.onsiteEndDate != null) {
                Integer onsiteDays = input.onsiteStartDate.daysBetween(input.onsiteEndDate) + 1;
                onsiteNeeded = onsiteDays < 30 && input.onsiteStartDate >= input.startDate && input.onsiteEndDate <= input.endDate;
            }

            // 3. Onsite gap (if needed): 1 week (Mon-Sun) containing onsiteStartDate
            Set<Date> onsiteGapDates = new Set<Date>();
            Date onsiteGapWeekStart = null;
            Date onsiteGapWeekEnd = null;
            if (onsiteNeeded) {
                Integer dayOfWeek = input.onsiteStartDate.toStartOfWeek().daysBetween(input.onsiteStartDate) + 1;
                Integer daysToMonday = (dayOfWeek == 1) ? -6 : 2 - dayOfWeek;
                onsiteGapWeekStart = input.onsiteStartDate.addDays(daysToMonday);
                onsiteGapWeekEnd = onsiteGapWeekStart.addDays(6);
                for (Date d = onsiteGapWeekStart; d <= onsiteGapWeekEnd; d = d.addDays(1)) {
                    onsiteGapDates.add(d);
                }
            }

            // 4. Calculate category date ranges and determine which categories are valid (work backwards)
            // We'll use days, not weeks, for flexibility
            Integer cat1Days = (input.cat1Weeks == null ? 0 : Integer.valueOf(input.cat1Weeks * 7));
            Integer cat2Days = (input.cat2Weeks == null ? 0 : Integer.valueOf(input.cat2Weeks * 7));
            Integer cat3Days = (input.cat3Weeks == null ? 0 : Integer.valueOf(input.cat3Weeks * 7));
            Integer postDays = (input.postWeeks == null ? 0 : Integer.valueOf(input.postWeeks * 7));

            // Track which categories are valid
            Boolean postValid = onsiteNeeded;
            Boolean cat3Valid = true;
            Boolean cat2Valid = true;
            Boolean cat1Valid = true;


            // Calculate post category range (if valid)
            Date postStart = null;
            Date postEnd = null;
            if (postValid) {
                postEnd = input.endDate;
                postStart = onsiteGapWeekEnd != null ? onsiteGapWeekEnd.addDays(1) : input.endDate.addDays(1); // If no onsite, post not valid
                if (postStart > postEnd) {
                    postValid = false;
                }
            }

            // Calculate cat3 range
            Date cat3End = postValid ? onsiteGapWeekStart.addDays(-1) : input.endDate;
            Date cat3Start = cat3End.addDays(-cat3Days + 1);

            // Calculate cat2 range
            Date cat2End = cat3Start.addDays(-1);
            Date cat2Start = cat2End.addDays(-cat2Days + 1);

            // Calculate cat1 range
            Date cat1End = cat2Start.addDays(-1);
            Date cat1Start = cat1End.addDays(-cat1Days + 1);

            // Trim category ranges to input range and set validity
            cat1Valid = (cat1End >= input.startDate && cat1Start <= input.endDate);
            cat2Valid = (cat2End >= input.startDate && cat2Start <= input.endDate);
            cat3Valid = (cat3End >= input.startDate && cat3Start <= input.endDate);
            postValid = (postEnd >= input.startDate && postStart <= input.endDate && postValid);

            // Calculate actual (trimmed) start/end for each valid category
            Date cat1ActualStart = cat1Valid ? (cat1Start > input.startDate ? cat1Start : input.startDate) : null;
            Date cat1ActualEnd = cat1Valid ? (cat1End < input.endDate ? cat1End : input.endDate) : null;
            Date cat2ActualStart = cat2Valid ? (cat2Start > input.startDate ? cat2Start : input.startDate) : null;
            Date cat2ActualEnd = cat2Valid ? (cat2End < input.endDate ? cat2End : input.endDate) : null;
            Date cat3ActualStart = cat3Valid ? (cat3Start > input.startDate ? cat3Start : input.startDate) : null;
            Date cat3ActualEnd = cat3Valid ? (cat3End < input.endDate ? cat3End : input.endDate) : null;
            Date postActualStart = postValid ? (postStart > input.startDate ? postStart : input.startDate) : null;
            Date postActualEnd = postValid ? (postEnd < input.endDate ? postEnd : input.endDate) : null;

            // 5. Redistribute percentages: sum valid, get diff from 100, add even split of diff to each valid
            Decimal cat1Pct = 0, cat2Pct = 0, cat3Pct = 0, postPct = 0;
            List<Decimal> origPcts = new List<Decimal>();
            List<String> validCats = new List<String>();
            if (cat1Valid) { validCats.add('cat1'); origPcts.add(input.cat1Percentage); }
            if (cat2Valid) { validCats.add('cat2'); origPcts.add(input.cat2Percentage); }
            if (cat3Valid) { validCats.add('cat3'); origPcts.add(input.cat3Percentage); }
            if (postValid) { validCats.add('post'); origPcts.add(input.postPercentage); }
            Integer validCount = validCats.size();
            Decimal sumValid = 0;
            for (Decimal pct : origPcts) sumValid += pct;
            Decimal diff = 100 - sumValid;
            Decimal addEach = validCount > 0 ? diff / validCount : 0;
            Integer idx = 0;
            for (String cat : validCats) {
                Decimal pct = origPcts[idx] + addEach;
                if (cat == 'cat1') cat1Pct = pct;
                if (cat == 'cat2') cat2Pct = pct;
                if (cat == 'cat3') cat3Pct = pct;
                if (cat == 'post') postPct = pct;
                idx++;
            }

            // 6. Create exceptions for each valid category, ensuring no overlap and onsite gap is its own exception
            List<pse__Schedule_Exception__c> allExceptions = new List<pse__Schedule_Exception__c>();

            // Exclude holidays for all categories
            Set<Date> excludeDates = new Set<Date>();
            excludeDates.addAll(holidayDates);

            // 6a. Onsite gap exception (if needed)
            if (onsiteNeeded && onsiteGapWeekStart != null && onsiteGapWeekEnd != null) {
                // Split onsite gap week at holidays
                addSplitExceptions(
                    onsiteGapWeekStart, onsiteGapWeekEnd, 0, input.numberOfWorkDays, input.scheduleId,
                    input.startDate, input.endDate, holidayDates, allExceptions, new List<pse__Schedule_Exception__c>()
                );
            }

            // Helper to create category exceptions, splitting at every holiday and onsite gap day
            Set<Date> allSplits = new Set<Date>();
            allSplits.addAll(holidayDates);
            allSplits.addAll(onsiteGapDates);

            // Track exceptions by category
            Map<String, List<pse__Schedule_Exception__c>> catExceptions = new Map<String, List<pse__Schedule_Exception__c>>{
                'cat1' => new List<pse__Schedule_Exception__c>(),
                'cat2' => new List<pse__Schedule_Exception__c>(),
                'cat3' => new List<pse__Schedule_Exception__c>(),
                'post' => new List<pse__Schedule_Exception__c>()
            };

            // Calculate usable workdays for each category
            Integer cat1UsableDays = (cat1Valid && cat1ActualStart != null && cat1ActualEnd != null && cat1ActualStart <= cat1ActualEnd)
                ? countUsableWorkdays(cat1ActualStart, cat1ActualEnd, allSplits) : 0;
            Integer cat2UsableDays = (cat2Valid && cat2ActualStart != null && cat2ActualEnd != null && cat2ActualStart <= cat2ActualEnd)
                ? countUsableWorkdays(cat2ActualStart, cat2ActualEnd, allSplits) : 0;
            Integer cat3UsableDays = (cat3Valid && cat3ActualStart != null && cat3ActualEnd != null && cat3ActualStart <= cat3ActualEnd)
                ? countUsableWorkdays(cat3ActualStart, cat3ActualEnd, allSplits) : 0;
            Integer postUsableDays = (postValid && postActualStart != null && postActualEnd != null && postActualStart <= postActualEnd)
                ? countUsableWorkdays(postActualStart, postActualEnd, allSplits) : 0;

            // Calculate hours per day for each category
            Decimal cat1HoursPerDay = (cat1UsableDays > 0) ? ((cat1Pct/100) * input.numberOfHours) / cat1UsableDays : 0;
            Decimal cat2HoursPerDay = (cat2UsableDays > 0) ? ((cat2Pct/100) * input.numberOfHours) / cat2UsableDays : 0;
            Decimal cat3HoursPerDay = (cat3UsableDays > 0) ? ((cat3Pct/100) * input.numberOfHours) / cat3UsableDays : 0;
            Decimal postHoursPerDay = (postUsableDays > 0) ? ((postPct/100) * input.numberOfHours) / postUsableDays : 0;

            // Debug logs for diagnosis
            System.debug('CAT1: start=' + cat1ActualStart + ', end=' + cat1ActualEnd + ', usableDays=' + cat1UsableDays + ', pct=' + cat1Pct + ', hoursPerDay=' + cat1HoursPerDay);
            System.debug('CAT2: start=' + cat2ActualStart + ', end=' + cat2ActualEnd + ', usableDays=' + cat2UsableDays + ', pct=' + cat2Pct + ', hoursPerDay=' + cat2HoursPerDay);
            System.debug('CAT3: start=' + cat3ActualStart + ', end=' + cat3ActualEnd + ', usableDays=' + cat3UsableDays + ', pct=' + cat3Pct + ', hoursPerDay=' + cat3HoursPerDay);
            System.debug('POST: start=' + postActualStart + ', end=' + postActualEnd + ', usableDays=' + postUsableDays + ', pct=' + postPct + ', hoursPerDay=' + postHoursPerDay);
            System.debug('allSplits (holidays+onsiteGap): ' + allSplits);

            // Cat1
            if (cat1Valid && cat1ActualStart != null && cat1ActualEnd != null && cat1ActualStart <= cat1ActualEnd) {
                ScheduleHoursDistributor.addSplitExceptions(cat1ActualStart, cat1ActualEnd, cat1HoursPerDay, input.numberOfWorkDays, input.scheduleId, input.startDate, input.endDate, allSplits, allExceptions, catExceptions.get('cat1'));
            }
            // Cat2
            if (cat2Valid && cat2ActualStart != null && cat2ActualEnd != null && cat2ActualStart <= cat2ActualEnd) {
                ScheduleHoursDistributor.addSplitExceptions(cat2ActualStart, cat2ActualEnd, cat2HoursPerDay, input.numberOfWorkDays, input.scheduleId, input.startDate, input.endDate, allSplits, allExceptions, catExceptions.get('cat2'));
            }
            // Cat3
            if (cat3Valid && cat3ActualStart != null && cat3ActualEnd != null && cat3ActualStart <= cat3ActualEnd) {
                ScheduleHoursDistributor.addSplitExceptions(cat3ActualStart, cat3ActualEnd, cat3HoursPerDay, input.numberOfWorkDays, input.scheduleId, input.startDate, input.endDate, allSplits, allExceptions, catExceptions.get('cat3'));
            }
            // Post
            if (postValid && postActualStart != null && postActualEnd != null && postActualStart <= postActualEnd) {
                ScheduleHoursDistributor.addSplitExceptions(postActualStart, postActualEnd, postHoursPerDay, input.numberOfWorkDays, input.scheduleId, input.startDate, input.endDate, allSplits, allExceptions, catExceptions.get('post'));
            }

            outputList.add(new ScheduleExceptionOutputWrapper(
                allExceptions,
                null
            ));
        } catch (Exception e) {
            return returnErrorWrapper('Error: ' + e.getMessage());
        }
        return outputList;
    }

    // Helper: Extracts all holiday dates from existing exceptions
    public static Set<Date> extractHolidayDates(List<pse__Schedule_Exception__c> existingExceptions) {
        Set<Date> holidayDates = new Set<Date>();
        if (existingExceptions != null) {
            for (pse__Schedule_Exception__c exc : existingExceptions) {
                if (exc == null || exc.pse__Date__c == null) continue;
                Date start = exc.pse__Date__c;
                Date endDate = exc.pse__End_Date__c == null ? start : exc.pse__End_Date__c;
                for (Date d = start; d <= endDate; d = d.addDays(1)) {
                    holidayDates.add(d);
                }
            }
        }
        return holidayDates;
    }

    // Helper: Creates and returns a single schedule exception record
    public static pse__Schedule_Exception__c createScheduleException(Id scheduleId, Date startDate, Date endDate, Integer workDays, Decimal hoursPerDay) {
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

    // Helper: Returns a wrapper with an error message
    private static List<ScheduleExceptionOutputWrapper> returnErrorWrapper(String errorMessage) {
        return new List<ScheduleExceptionOutputWrapper>{
            new ScheduleExceptionOutputWrapper(
                new List<pse__Schedule_Exception__c>(),
                errorMessage
            )
        };
    }

    // Helper: Adds split exceptions for a category, splitting at every holiday and onsite gap day
    public static void addSplitExceptions(
        Date segStart, Date segEnd, Decimal hoursPerDay, Integer workDays, Id scheduleId, Date inputStart, Date inputEnd, Set<Date> allSplits, List<pse__Schedule_Exception__c> allExceptions, List<pse__Schedule_Exception__c> catList
    ) {
        Date currStart = null;
        for (Date d = segStart; d <= segEnd.addDays(1); d = d.addDays(1)) {
            Boolean isSplit = (d > segEnd) || allSplits.contains(d);
            if (currStart == null && !allSplits.contains(d) && d >= inputStart && d <= inputEnd) {
                currStart = d;
            } else if (currStart != null && !isSplit && d >= inputStart && d <= inputEnd) {
                // continue current segment
            } else if (currStart != null && isSplit) {
                pse__Schedule_Exception__c exc = createScheduleException(scheduleId, currStart, d.addDays(-1), workDays, hoursPerDay);
                allExceptions.add(exc);
                catList.add(exc);
                currStart = null;
            }
        }
    }

    // Helper: Counts usable workdays (Mon-Fri) between two dates, excluding holidays and onsite gap days
    public static Integer countUsableWorkdays(Date start, Date endDate, Set<Date> excludeDates) {
        Integer count = 0;
        for (Date d = start; d <= endDate; d = d.addDays(1)) {
            Boolean weekday = isWeekday(d);
            Boolean excluded = excludeDates.contains(d);
            if (weekday && !excluded) {
                count++;
            }
            System.debug('countUsableWorkdays: date=' + d + ', isWeekday=' + weekday + ', isExcluded=' + excluded + ', runningCount=' + count);
        }
        System.debug('countUsableWorkdays: FINAL count for range ' + start + ' to ' + endDate + ' (excludes=' + excludeDates + ') = ' + count);
        return count;
    }

    // Helper: Returns true if the date is a weekday (Mon-Fri)
    public static Boolean isWeekday(Date d) {
        Integer dow = d.toStartOfWeek().daysBetween(d) + 1; // 1=Monday, 7=Sunday
        return dow >= 1 && dow <= 5;
    }


    // Wrapper class: Holds output schedule exceptions and calculated values
    public class ScheduleExceptionOutputWrapper {
        @InvocableVariable(label='Schedule Exceptions' description='List of Schedule Exception records')
        public List<pse__Schedule_Exception__c> scheduleExceptions;

        @InvocableVariable(label='Error Message' description='Error encountered during execution')
        public String errorMessage;

        public ScheduleExceptionOutputWrapper(
            List<pse__Schedule_Exception__c> exceptions,
            String error
        ) {
            this.scheduleExceptions = exceptions;
            this.errorMessage = error;
        }
    }

    // Input wrapper class: Holds parameters from Flow for schedule generation
    public class ScheduleInput {
        @InvocableVariable(label='Onsite Start Date') public Date onsiteStartDate;
        @InvocableVariable(label='Onsite End Date') public Date onsiteEndDate;
        @InvocableVariable(label='Schedule ID') public Id scheduleId;
        @InvocableVariable(label='Start Date') public Date startDate;
        @InvocableVariable(label='End Date') public Date endDate;
        @InvocableVariable(label='Number of Hours') public Decimal numberOfHours;
        @InvocableVariable(label='Number of Work Days') public Integer numberOfWorkDays;

        @InvocableVariable(label='Category 1 Weeks') public Decimal cat1Weeks;
        @InvocableVariable(label='Category 2 Weeks') public Decimal cat2Weeks;
        @InvocableVariable(label='Category 3 Weeks') public Decimal cat3Weeks;
        @InvocableVariable(label='Post Weeks') public Decimal postWeeks;

        @InvocableVariable(label='Category 1 Percentage') public Decimal cat1Percentage;
        @InvocableVariable(label='Category 2 Percentage') public Decimal cat2Percentage;
        @InvocableVariable(label='Category 3 Percentage') public Decimal cat3Percentage;
        @InvocableVariable(label='Post Percentage') public Decimal postPercentage;

        @InvocableVariable(label='Existing Schedule Exceptions') 
        public List<pse__Schedule_Exception__c> existingExceptions;

        public Date cat1StartDate;
        public Date cat1EndDate;
        public Date cat2StartDate;
        public Date cat2EndDate;
        public Date cat3StartDate;
        public Date cat3EndDate;
        public Date postStartDate;
        public Date postEndDate;
    }
}