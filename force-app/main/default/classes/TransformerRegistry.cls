public with sharing class TransformerRegistry {
    private static final Map<String, Type> REGISTRY = new Map<String, Type>{
        'WIDEORBIT_TV'             => WideOrbitTransformer.class,
        'WIDEORBIT_RADIO'          => WideOrbitTransformer.class,
        'STRATA'                   => StrataTransformer.class,
        'COXREPS'                  => CoxRepsTransformer.class,
        'OPERATIVE'                => OperativeTransformer.class,
        'COUNTERPOINT_CALENDAR'    => CounterpointTransformer.class,
        'COUNTERPOINT_BROADCAST'   => CounterpointTransformer.class
    };

    public static SourceSystemTransformer getTransformer(String sourceSystemCode) {
        Type t = REGISTRY.get(sourceSystemCode);
        if (t == null) {
            throw new IngestException('No transformer registered for source system code: ' + sourceSystemCode);
        }
        return (SourceSystemTransformer) t.newInstance();
    }
}
