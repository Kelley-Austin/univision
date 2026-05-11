List<RecordTypeInfo> oppRTs = Schema.SObjectType.Opportunity.getRecordTypeInfos();
for (RecordTypeInfo r : oppRTs) {
    System.debug('OPP_RT: ' + r.getDeveloperName() + ' | ' + r.getRecordTypeId() + ' | available=' + r.isAvailable());
}
List<RecordTypeInfo> accRTs = Schema.SObjectType.Account.getRecordTypeInfos();
for (RecordTypeInfo r : accRTs) {
    System.debug('ACC_RT: ' + r.getDeveloperName() + ' | ' + r.getRecordTypeId() + ' | available=' + r.isAvailable());
}
