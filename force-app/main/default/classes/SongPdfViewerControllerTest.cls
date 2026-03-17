@isTest
private class SongPdfViewerControllerTest {

    @testSetup
    static void setup() {
        Song__c songWithPdf = new Song__c(
            Name = 'Song With PDF',
            Scroll_Speed__c = 10,
            Zoom__c = 2.0,
            Song_Zone_Speeds__c = '0%-50%:8,50%-100%:12'
        );
        insert songWithPdf;

        Song__c songNoFile = new Song__c(
            Name = 'Song No File',
            Scroll_Speed__c = 5
        );
        insert songNoFile;

        Song__c songWithTxt = new Song__c(
            Name = 'Song With Txt',
            Scroll_Speed__c = 5
        );
        insert songWithTxt;

        // PDF attached to songWithPdf
        ContentVersion cvPdf = new ContentVersion(
            Title = 'Fake PDF',
            PathOnClient = 'fake.pdf',
            VersionData = Blob.valueOf('%PDF-1.4 fake content')
        );
        insert cvPdf;

        ContentVersion insertedPdf = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cvPdf.Id];
        insert new ContentDocumentLink(
            LinkedEntityId = songWithPdf.Id,
            ContentDocumentId = insertedPdf.ContentDocumentId,
            ShareType = 'V',
            Visibility = 'AllUsers'
        );

        // Non-PDF file attached to songWithTxt
        ContentVersion cvTxt = new ContentVersion(
            Title = 'Fake Txt',
            PathOnClient = 'fake.txt',
            VersionData = Blob.valueOf('plain text')
        );
        insert cvTxt;

        ContentVersion insertedTxt = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cvTxt.Id];
        insert new ContentDocumentLink(
            LinkedEntityId = songWithTxt.Id,
            ContentDocumentId = insertedTxt.ContentDocumentId,
            ShareType = 'V',
            Visibility = 'AllUsers'
        );
    }

    @isTest
    static void testConstructorWithIdParam() {
        Song__c song = [SELECT Id FROM Song__c WHERE Name = 'Song With PDF' LIMIT 1];

        ApexPages.currentPage().getParameters().put('id', song.Id);

        Test.startTest();
        SongPdfViewerController ctrl = new SongPdfViewerController();
        Test.stopTest();

        System.assertEquals('Song With PDF', ctrl.songName);
        System.assertEquals(song.Id, ctrl.songId);
        System.assertEquals(10, ctrl.scrollSpeed);
        System.assertEquals(2.0, ctrl.zoom);
        System.assertNotEquals(null, ctrl.zoneSpeedsJson);
        System.assert(ctrl.zoneSpeedsJson.contains('startPct'));
        System.assert(String.isBlank(ctrl.errorMessage));
    }

    @isTest
    static void testConstructorWithSongIdParam() {
        Song__c song = [SELECT Id FROM Song__c WHERE Name = 'Song With PDF' LIMIT 1];

        ApexPages.currentPage().getParameters().put('songId', song.Id);

        Test.startTest();
        SongPdfViewerController ctrl = new SongPdfViewerController();
        Test.stopTest();

        System.assertEquals(song.Id, ctrl.songId);
        System.assertEquals('Song With PDF', ctrl.songName);
    }

    @isTest
    static void testConstructorNoSongId() {
        Test.startTest();
        SongPdfViewerController ctrl = new SongPdfViewerController();
        Test.stopTest();

        System.assertEquals('No Song ID provided. Use ?id=xxx or ?songId=xxx', ctrl.errorMessage);
    }

    @isTest
    static void testConstructorNoFile() {
        Song__c song = [SELECT Id FROM Song__c WHERE Name = 'Song No File' LIMIT 1];

        ApexPages.currentPage().getParameters().put('id', song.Id);

        Test.startTest();
        SongPdfViewerController ctrl = new SongPdfViewerController();
        Test.stopTest();

        System.assertEquals('No file linked to this song.', ctrl.errorMessage);
    }

    @isTest
    static void testConstructorNoPdf() {
        Song__c song = [SELECT Id FROM Song__c WHERE Name = 'Song With Txt' LIMIT 1];

        ApexPages.currentPage().getParameters().put('id', song.Id);

        Test.startTest();
        SongPdfViewerController ctrl = new SongPdfViewerController();
        Test.stopTest();

        System.assertEquals('No PDF file attached to this song.', ctrl.errorMessage);
    }

    @isTest
    static void testConstructorSongNotFound() {
        ContentDocument cd = [SELECT Id FROM ContentDocument LIMIT 1];
        ApexPages.currentPage().getParameters().put('id', cd.Id);

        Test.startTest();
        SongPdfViewerController ctrl = new SongPdfViewerController();
        Test.stopTest();

        System.assertEquals('Song not found.', ctrl.errorMessage);
    }

    @isTest
    static void testConstructorDefaultZoneSpeed() {
        Song__c song = [SELECT Id FROM Song__c WHERE Name = 'Song With PDF' LIMIT 1];
        song.Song_Zone_Speeds__c = null;
        update song;

        ApexPages.currentPage().getParameters().put('id', song.Id);

        Test.startTest();
        SongPdfViewerController ctrl = new SongPdfViewerController();
        Test.stopTest();

        System.assertNotEquals(null, ctrl.zoneSpeedsJson);
        System.assert(ctrl.zoneSpeedsJson.contains('100'));
    }

    @isTest
    static void testGetPdfBase64Null() {
        String result = SongPdfViewerController.getPdfBase64(null);
        System.assertEquals('', result);
    }

    @isTest
    static void testGetPdfBase64NoLinks() {
        Song__c song = [SELECT Id FROM Song__c WHERE Name = 'Song No File' LIMIT 1];

        String result = SongPdfViewerController.getPdfBase64(song.Id);
        System.assertEquals('', result);
    }

    @isTest
    static void testGetPdfBase64WithPdf() {
        Song__c song = [SELECT Id FROM Song__c WHERE Name = 'Song With PDF' LIMIT 1];

        Test.startTest();
        String result = SongPdfViewerController.getPdfBase64(song.Id);
        Test.stopTest();

        System.assertNotEquals('', result);
        System.assert(result.length() > 0);
    }

    @isTest
    static void testSaveZonesActionSuccess() {
        Song__c song = [SELECT Id FROM Song__c WHERE Name = 'Song With PDF' LIMIT 1];

        ApexPages.currentPage().getParameters().put('id', song.Id);
        SongPdfViewerController ctrl = new SongPdfViewerController();
        ctrl.zoneStrToSave = '0%-33%:9,33%-66%:5,66%-100%:12';

        Test.startTest();
        PageReference pr = ctrl.saveZonesAction();
        Test.stopTest();

        System.assertEquals(null, pr);
        Song__c updated = [SELECT Song_Zone_Speeds__c, Scroll_Speed__c FROM Song__c WHERE Id = :song.Id];
        System.assertEquals(9, updated.Scroll_Speed__c);
    }

    @isTest
    static void testSaveZonesActionBlank() {
        Song__c song = [SELECT Id FROM Song__c WHERE Name = 'Song With PDF' LIMIT 1];

        ApexPages.currentPage().getParameters().put('id', song.Id);
        SongPdfViewerController ctrl = new SongPdfViewerController();
        ctrl.zoneStrToSave = '';

        PageReference pr = ctrl.saveZonesAction();
        System.assertEquals(null, pr);
    }

    @isTest
    static void testSaveZonesActionInvalidZones() {
        Song__c song = [SELECT Id FROM Song__c WHERE Name = 'Song With PDF' LIMIT 1];

        ApexPages.currentPage().getParameters().put('id', song.Id);
        SongPdfViewerController ctrl = new SongPdfViewerController();
        ctrl.zoneStrToSave = '0%-50%:9,60%-100%:5';

        PageReference pr = ctrl.saveZonesAction();
        System.assertEquals(null, pr);
        System.assert(ApexPages.getMessages().size() > 0);
    }

    @isTest
    static void testSaveZoneSpeedsAjaxValid() {
        Song__c song = [SELECT Id FROM Song__c WHERE Name = 'Song With PDF' LIMIT 1];
        String zoneStr = '0%-33%:9,33%-66%:3,66%-100%:10';

        Test.startTest();
        String result = SongPdfViewerController.saveZoneSpeedsAjax(song.Id, zoneStr);
        Test.stopTest();

        System.assertEquals('success', result);
        Song__c updated = [SELECT Song_Zone_Speeds__c, Scroll_Speed__c FROM Song__c WHERE Id = :song.Id];
        System.assert(updated.Song_Zone_Speeds__c.contains('33'));
        System.assertEquals(9, updated.Scroll_Speed__c);
    }

    @isTest
    static void testSaveZoneSpeedsAjaxEmpty() {
        Song__c song = [SELECT Id FROM Song__c WHERE Name = 'Song With PDF' LIMIT 1];

        String result = SongPdfViewerController.saveZoneSpeedsAjax(song.Id, '');
        System.assert(result.contains('empty'));
    }

    @isTest
    static void testSaveZoneSpeedsAjaxNonContiguous() {
        Song__c song = [SELECT Id FROM Song__c WHERE Name = 'Song With PDF' LIMIT 1];

        String result = SongPdfViewerController.saveZoneSpeedsAjax(song.Id, '0%-50%:9,60%-100%:5');
        System.assert(result.contains('contiguous'));
    }

    @isTest
    static void testSaveZoneSpeedsAjaxInvalidFormat() {
        Song__c song = [SELECT Id FROM Song__c WHERE Name = 'Song With PDF' LIMIT 1];

        String result = SongPdfViewerController.saveZoneSpeedsAjax(song.Id, 'badformat');
        System.assert(result.contains('Invalid'));
    }

    @isTest
    static void testSaveZoneSpeedsAjaxSpeedOutOfRange() {
        Song__c song = [SELECT Id FROM Song__c WHERE Name = 'Song With PDF' LIMIT 1];

        String result = SongPdfViewerController.saveZoneSpeedsAjax(song.Id, '0%-50%:25,50%-100%:5');
        System.assert(result.contains('Speed must be 1-20'));
    }

    @isTest
    static void testSaveSpeedAjaxValid() {
        Song__c song = [SELECT Id FROM Song__c WHERE Name = 'Song With PDF' LIMIT 1];

        Test.startTest();
        String result = SongPdfViewerController.saveSpeedAjax(song.Id, 15);
        Test.stopTest();

        System.assertEquals('success', result);
        Song__c updated = [SELECT Scroll_Speed__c FROM Song__c WHERE Id = :song.Id];
        System.assertEquals(15, updated.Scroll_Speed__c);
    }

    @isTest
    static void testSaveSpeedAjaxOutOfRange() {
        Song__c song = [SELECT Id FROM Song__c WHERE Name = 'Song With PDF' LIMIT 1];

        String result = SongPdfViewerController.saveSpeedAjax(song.Id, 99);
        System.assert(result.contains('Speed must be between 1 and 20'));
    }

    @isTest
    static void testSaveZoomAjaxValid() {
        Song__c song = [SELECT Id FROM Song__c WHERE Name = 'Song With PDF' LIMIT 1];

        Test.startTest();
        String result = SongPdfViewerController.saveZoomAjax(song.Id, 2.75);
        Test.stopTest();

        System.assertEquals('success', result);
        Song__c updated = [SELECT Zoom__c FROM Song__c WHERE Id = :song.Id];
        System.assertEquals(2.75, updated.Zoom__c);
    }
}
