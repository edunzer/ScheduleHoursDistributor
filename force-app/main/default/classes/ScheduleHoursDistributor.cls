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
            if (input.numberOfHours == null) return returnErrorWrapper('Error: Number of Hours cannot be null.');
            if (input.numberOfWorkDays == null) return returnErrorWrapper('Error: Number of Work Days cannot be null.');
            if (input.cat1Weeks == null || input.cat2Weeks == null || input.cat3Weeks == null || input.postWeeks == null)
                return returnErrorWrapper('Error: Week values cannot be null.');
            if (input.cat1Percentage == null || input.cat2Percentage == null || input.cat3Percentage == null || input.postPercentage == null)
                return returnErrorWrapper('Error: Percentage values cannot be null.');
            if ((input.onsiteStartDate != null && input.onsiteEndDate == null) || (input.onsiteStartDate == null && input.onsiteEndDate != null))
                return returnErrorWrapper('Error: Both Onsite Start Date and Onsite End Date must be provided.');

            // 1. Calculate holidays
            Set<Date> holidayDates = extractHolidayDates(input.existingExceptions);

            // 2. Onsite needed check
            Boolean onsiteNeeded = false;
            if (input.onsiteStartDate != null && input.onsiteEndDate != null) {
                Integer onsiteDays = input.onsiteStartDate.daysBetween(input.onsiteEndDate) + 1;
                onsiteNeeded = onsiteDays < 30 && input.onsiteStartDate >= input.startDate && input.onsiteEndDate <= input.endDate;
            }

            // 3. Onsite gap (if needed): 1 week (Mon-Sun) containing onsiteStartDate, but only non-holiday days
            Set<Date> onsiteGapDates = new Set<Date>();
            Date onsiteGapWeekStart = null;
            Date onsiteGapWeekEnd = null;
            if (onsiteNeeded) {
                Integer dayOfWeek = input.onsiteStartDate.toStartOfWeek().daysBetween(input.onsiteStartDate) + 1;
                Integer daysToMonday = (dayOfWeek == 1) ? -6 : 2 - dayOfWeek;
                onsiteGapWeekStart = input.onsiteStartDate.addDays(daysToMonday);
                onsiteGapWeekEnd = onsiteGapWeekStart.addDays(6);
                for (Date d = onsiteGapWeekStart; d <= onsiteGapWeekEnd; d = d.addDays(1)) {
                    if (!holidayDates.contains(d)) {
                        onsiteGapDates.add(d);
                    }
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
            if (cat3Start < input.startDate) {
                // Not enough room for cat3, drop and redistribute
                cat3Valid = false;
                cat3Start = null;
                cat3End = null;
            }
            // If cat3 is dropped, post gets its hours

            // Calculate cat2 range
            Date cat2End = cat3Valid && cat3Start != null ? cat3Start.addDays(-1) : (postValid && postStart != null ? postStart.addDays(-1) : input.endDate);
            Date cat2Start = cat2End.addDays(-cat2Days + 1);
            if (cat2Start < input.startDate) {
                cat2Valid = false;
                cat2Start = null;
                cat2End = null;
            }

            // Calculate cat1 range
            Date cat1End = cat2Valid && cat2Start != null ? cat2Start.addDays(-1) : (cat3Valid && cat3Start != null ? cat3Start.addDays(-1) : (postValid && postStart != null ? postStart.addDays(-1) : input.endDate));
            Date cat1Start = cat1End.addDays(-cat1Days + 1);
            if (cat1Start < input.startDate) {
                cat1Valid = false;
                cat1Start = null;
                cat1End = null;
            }

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

            // 6. Create exceptions for each valid category
            List<pse__Schedule_Exception__c> allExceptions = new List<pse__Schedule_Exception__c>();
            Decimal hoursPerWeekCat1 = 0, hoursPerWeekCat2 = 0, hoursPerWeekCat3 = 0, hoursPerWeekPost = 0;

            // Helper to create exceptions for a category
            // Exclude holidays and onsite gap days
            Set<Date> excludeDates = new Set<Date>();
            excludeDates.addAll(holidayDates);
            excludeDates.addAll(onsiteGapDates);

            if (cat1Valid && cat1Start != null && cat1End != null && cat1Start <= cat1End) {
                List<Date> cat1DaysList = new List<Date>();
                for (Date d = cat1Start; d <= cat1End; d = d.addDays(1)) {
                    if (!excludeDates.contains(d) && d >= input.startDate && d <= input.endDate) cat1DaysList.add(d);
                }
                Integer usableDays = cat1DaysList.size();
                hoursPerWeekCat1 = (usableDays > 0) ? ((cat1Pct/100) * input.numberOfHours) / (usableDays/7.0) : 0;
                if (usableDays > 0) {
                    allExceptions.add(createScheduleException(input.scheduleId, cat1Start, cat1End, input.numberOfWorkDays, hoursPerWeekCat1));
                }
            }
            if (cat2Valid && cat2Start != null && cat2End != null && cat2Start <= cat2End) {
                List<Date> cat2DaysList = new List<Date>();
                for (Date d = cat2Start; d <= cat2End; d = d.addDays(1)) {
                    if (!excludeDates.contains(d) && d >= input.startDate && d <= input.endDate) cat2DaysList.add(d);
                }
                Integer usableDays = cat2DaysList.size();
                hoursPerWeekCat2 = (usableDays > 0) ? ((cat2Pct/100) * input.numberOfHours) / (usableDays/7.0) : 0;
                if (usableDays > 0) {
                    allExceptions.add(createScheduleException(input.scheduleId, cat2Start, cat2End, input.numberOfWorkDays, hoursPerWeekCat2));
                }
            }
            if (cat3Valid && cat3Start != null && cat3End != null && cat3Start <= cat3End) {
                List<Date> cat3DaysList = new List<Date>();
                for (Date d = cat3Start; d <= cat3End; d = d.addDays(1)) {
                    if (!excludeDates.contains(d) && d >= input.startDate && d <= input.endDate) cat3DaysList.add(d);
                }
                Integer usableDays = cat3DaysList.size();
                hoursPerWeekCat3 = (usableDays > 0) ? ((cat3Pct/100) * input.numberOfHours) / (usableDays/7.0) : 0;
                if (usableDays > 0) {
                    allExceptions.add(createScheduleException(input.scheduleId, cat3Start, cat3End, input.numberOfWorkDays, hoursPerWeekCat3));
                }
            }
            if (postValid && postStart != null && postEnd != null && postStart <= postEnd) {
                List<Date> postDaysList = new List<Date>();
                for (Date d = postStart; d <= postEnd; d = d.addDays(1)) {
                    if (!excludeDates.contains(d) && d >= input.startDate && d <= input.endDate) postDaysList.add(d);
                }
                Integer usableDays = postDaysList.size();
                hoursPerWeekPost = (usableDays > 0) ? ((postPct/100) * input.numberOfHours) / (usableDays/7.0) : 0;
                if (usableDays > 0) {
                    allExceptions.add(createScheduleException(input.scheduleId, postStart, postEnd, input.numberOfWorkDays, hoursPerWeekPost));
                }
            }

            outputList.add(new ScheduleExceptionOutputWrapper(
                allExceptions,
                hoursPerWeekCat1,
                hoursPerWeekCat2,
                hoursPerWeekCat3,
                hoursPerWeekPost,
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
                holidayDates.add(exc.pse__Date__c);
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
                0, 0, 0, 0, errorMessage
            )
        };
    }

    // Wrapper class: Holds output schedule exceptions and calculated values
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
    
        @InvocableVariable(label='Error Message' description='Error encountered during execution')
        public String errorMessage;
    
        public ScheduleExceptionOutputWrapper(List<pse__Schedule_Exception__c> exceptions, Decimal cat1Hours, Decimal cat2Hours, Decimal cat3Hours, Decimal postHours, String error) {
            this.scheduleExceptions = exceptions;
            this.hoursPerWeekCat1 = cat1Hours;
            this.hoursPerWeekCat2 = cat2Hours;
            this.hoursPerWeekCat3 = cat3Hours;
            this.hoursPerWeekPost = postHours;
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
