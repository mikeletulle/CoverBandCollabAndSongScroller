@isTest
private class SetListPdfViewerControllerTest {

    @testSetup
    static void setup() {
        // Create a Song__c record
        Song__c song = new Song__c(Name = 'Test Song');
        insert song;

        // Create a Set_List__c record (replace with required fields if any)
        Set_List__c setList = new Set_List__c(Name = 'Test Set List');
        insert setList;

        // Link song to set list
        Set_List_Song__c setListSong = new Set_List_Song__c(
            Set_List__c = setList.Id,
            Song__c = song.Id,
            Order_Number__c = 1
        );
        insert setListSong;

        // Create a ContentVersion (simulate attached PDF)
        ContentVersion cv = new ContentVersion(
            Title = 'Fake PDF',
            PathOnClient = 'fake.pdf',
            VersionData = Blob.valueOf('%PDF-1.4 fake content')
        );
        insert cv;

        // Get the ContentDocumentId from inserted ContentVersion
        ContentVersion inserted = [SELECT Id, ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id];

        // Link it to the song
        ContentDocumentLink cdl = new ContentDocumentLink(
            LinkedEntityId = song.Id,
            ContentDocumentId = inserted.ContentDocumentId,
            ShareType = 'V',
            Visibility = 'AllUsers'
        );
        insert cdl;
    }

    @isTest
    static void testValidController() {
        Set_List__c setList = [SELECT Id FROM Set_List__c LIMIT 1];
        Song__c song = [SELECT Id FROM Song__c LIMIT 1];

        // Simulate URL params
        ApexPages.currentPage().getParameters().put('setlistId', setList.Id);
        ApexPages.currentPage().getParameters().put('selectedSongId', song.Id);

        Test.startTest();
        SetListPdfViewerController controller = new SetListPdfViewerController();
        Test.stopTest();

        System.assertEquals('Test Song', controller.songName);
        System.assert(controller.songDropdownHtml.contains('option'));
        System.assert(controller.scrollSpeed > 0);
        System.assert(controller.zoom > 0);
        System.assertNotEquals(null, controller.zoneSpeedsJson);
        System.assert(controller.zoneSpeedsJson.contains('startPct'));
    }

    @isTest
    static void testMissingSetListId() {
        // No params
        Test.startTest();
        SetListPdfViewerController controller = new SetListPdfViewerController();
        Test.stopTest();

        System.assertEquals('No Set List ID provided.', controller.errorMessage);
    }

    @isTest
    static void testSaveSpeedAjaxValid() {
        Song__c song = [SELECT Id FROM Song__c LIMIT 1];

        Test.startTest();
        String result = SetListPdfViewerController.saveSpeedAjax(song.Id, 15);
        Test.stopTest();

        System.assertEquals('success', result);
        Song__c updated = [SELECT Scroll_Speed__c FROM Song__c WHERE Id = :song.Id];
        System.assertEquals(15, updated.Scroll_Speed__c);
    }

    @isTest
    static void testSaveSpeedAjaxOutOfRange() {
        Song__c song = [SELECT Id FROM Song__c LIMIT 1];

        String result = SetListPdfViewerController.saveSpeedAjax(song.Id, 99);
        System.assert(result.contains('Speed must be between 1 and 20'));
    }

    @isTest
    static void testSaveZoomAjaxValid() {
        Song__c song = [SELECT Id FROM Song__c LIMIT 1];

        Test.startTest();
        String result = SetListPdfViewerController.saveZoomAjax(song.Id, 2.75);
        Test.stopTest();

        System.assertEquals('success', result);
        Song__c updated = [SELECT Zoom__c FROM Song__c WHERE Id = :song.Id];
        System.assertEquals(2.75, updated.Zoom__c);
    }

    @isTest
    static void testSaveZoneSpeedsAjaxValid() {
        Song__c song = [SELECT Id FROM Song__c LIMIT 1];
        String zoneStr = '0%-33%:9,33%-66%:3,66%-100%:10';

        Test.startTest();
        String result = SetListPdfViewerController.saveZoneSpeedsAjax(song.Id, zoneStr);
        Test.stopTest();

        System.assertEquals('success', result);
        Song__c updated = [SELECT Song_Zone_Speeds__c, Scroll_Speed__c FROM Song__c WHERE Id = :song.Id];
        System.assertEquals(zoneStr, updated.Song_Zone_Speeds__c);
        System.assertEquals(9, updated.Scroll_Speed__c);
    }

    @isTest
    static void testSaveZoneSpeedsAjaxInvalid() {
        Song__c song = [SELECT Id FROM Song__c LIMIT 1];

        String result = SetListPdfViewerController.saveZoneSpeedsAjax(song.Id, '0%-50%:9,60%-100%:5');
        System.assert(result.contains('contiguous'));
    }

    @isTest
    static void testGetPdfBase64() {
        Song__c song = [SELECT Id FROM Song__c LIMIT 1];
        String result = SetListPdfViewerController.getPdfBase64(song.Id);
        System.assertNotEquals('', result);
    }

    @isTest
    static void testSaveZonesAction() {
        Set_List__c setList = [SELECT Id FROM Set_List__c LIMIT 1];
        Song__c song = [SELECT Id FROM Song__c LIMIT 1];
        ApexPages.currentPage().getParameters().put('setlistId', setList.Id);
        ApexPages.currentPage().getParameters().put('selectedSongId', song.Id);
        SetListPdfViewerController ctrl = new SetListPdfViewerController();
        ctrl.zoneStrToSave = '0%-100%:8';
        ctrl.saveZonesAction();
    }
}
