public without sharing class LimitStatus {
    public Static Map<String,System.OrgLimit> limitsMap {
        get{
            return OrgLimits.getMap();
        }
    }
    public static Integer getLimitValue(String limitName){return limitsMap.get(limitName).getValue();}
    public static Integer getLimitTotal(String limitName){return limitsMap.get(limitName).getLimit();}
    public static Integer getLimitAvail(String limitName){return getLimitTotal(limitName) - getLimitValue(limitName);}
    public static Boolean isLimitHit(String limitName){return (getLimitAvail(limitName)<=0);}
    public static String stringVal{
        get{
            if(stringval==null){
                for(string s : limitsMap.keySet()){
                    stringVal += s + ': ' + limitsMap.get(s).getValue() + ' out of ' + limitsMap.get(s).getLimit() + '\n';
                }   
            }
            return stringVal;
        }
        set;
    }
}