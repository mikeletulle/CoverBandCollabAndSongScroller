public with sharing class SetListReorderController {
    public class SetListSongDTO {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;          // <-- will hold Song__r.Name
        @AuraEnabled public Decimal currentOrder;

        public SetListSongDTO(Id id, String name, Decimal currentOrder) {
            this.id = id;
            this.name = name;
            this.currentOrder = currentOrder;
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<SetListSongDTO> getSetListSongs(Id setListId) {
        if (setListId == null) return new List<SetListSongDTO>();

        // Pull the related Song's Name (Song__r.Name)
        List<Set_List_Song__c> songs = [
            SELECT Id, Order_Number__c, Song__r.Name
            FROM Set_List_Song__c
            WHERE Set_List__c = :setListId
            ORDER BY Order_Number__c ASC, CreatedDate ASC
        ];

        List<SetListSongDTO> out = new List<SetListSongDTO>();
        for (Set_List_Song__c s : songs) {
            String songName = (s.Song__r != null) ? s.Song__r.Name : null;
            out.add(new SetListSongDTO(s.Id, songName, s.Order_Number__c));
        }
        return out;
    }

    public class UpdateReq {
        @AuraEnabled public Id id;
        @AuraEnabled public Decimal orderNumber;
    }

    /** When true, SetListSongTrigger skips its reorder logic to avoid corrupting our bulk update. */
    public static Boolean isBulkReorderInProgress = false;

    @AuraEnabled
    public static void updateOrdersOrdered(List<Id> orderedIds) {
        if (orderedIds == null || orderedIds.isEmpty()) return;

        Set_List_Song__c first = [SELECT Set_List__c FROM Set_List_Song__c WHERE Id = :orderedIds[0] LIMIT 1];
        Id setListId = first.Set_List__c;
        if (setListId == null) return;

        Map<Id, Integer> positionById = new Map<Id, Integer>();
        for (Integer i = 0; i < orderedIds.size(); i++) {
            if (!positionById.containsKey(orderedIds[i])) {
                positionById.put(orderedIds[i], i + 1);
            }
        }

        List<Set_List_Song__c> allSongs = [
            SELECT Id, Order_Number__c
            FROM Set_List_Song__c
            WHERE Set_List__c = :setListId
        ];

        Integer nextPosition = orderedIds.size() + 1;
        List<Set_List_Song__c> toUpdate = new List<Set_List_Song__c>();
        for (Set_List_Song__c row : allSongs) {
            Integer newOrder = positionById.get(row.Id);
            if (newOrder == null) {
                newOrder = nextPosition++;
            }
            if (row.Order_Number__c != newOrder) {
                row.Order_Number__c = Decimal.valueOf(newOrder);
                toUpdate.add(row);
            }
        }

        if (!toUpdate.isEmpty()) {
            try {
                isBulkReorderInProgress = true;
                update toUpdate;
            } finally {
                isBulkReorderInProgress = false;
            }
        }
    }

}
