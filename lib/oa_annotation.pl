:- module(oa_annotation, [
	      rdf_add_annotation/2,
	      rdf_get_annotation/2,
	      rdf_get_annotation_target/2,
	      rdf_get_annotation_by_tfa/5,
	      rdf_remove_annotation/2,
	      rdf_has_graph/4
	  ]).
/** <module> Open Annotation Prolog API

Some simple predicates to create, get and remove open annotation
triples. Since OA is a bit of a moving target, this may not be
completely following the spec... Especially not when dealing with
literal body tags.

@author Jacco van Ossenbruggen
@license LGPL
*/

:- use_module(library(semweb/rdf_db)).
:- use_module(library(semweb/rdfs)).
:- use_module(library(semweb/rdf_label)).
:- use_module(library(oa_schema)).
:- use_module(library(graph_version)).

:- rdf_meta
	normalize_property(r,o),
	normalize_object(r,o,o),
	rdf_has_graph(r,r,r,r).

:- rdf_register_ns(oa_target,   'http://localhost/.well-known/genid/oa/target/target_').
:- rdf_register_ns(oa_selector, 'http://localhost/.well-known/genid/oa/target/selector_').

upgrade_property_name(annotated, annotatedAt).
upgrade_property_name(annotator, annotatedBy).
upgrade_property_name(P,P).

normalize_property(rdf:type, '@type') :-
	!.

normalize_property(Property, NormalizedProperty) :-
	rdf_global_id(_NS:Local, Property),
	upgrade_property_name(Local,NormalizedProperty),
	!.

normalize_object(literal(Object), hasBody, ObjectDict) :-
	ObjectDict = body{'@value':Object},
	!.
normalize_object(Object, hasBody, ObjectDict) :-
	rdf_is_resource(Object),
	ObjectDict = body{'@id':Object},
	!.

normalize_object(TargetNode, hasTarget, TargetDict) :-
	rdfs_individual_of(TargetNode, oa:'SpecificResource'),
	rdf_has(TargetNode, oa:hasSource, Source),
	rdf_has(TargetNode, oa:hasSelector, SelectorNode),
	rdf_has(SelectorNode, rdf:value, literal(Value)),
	(   rdf_has(SelectorNode, oa:x, literal(type(_,X))),
	    rdf_has(SelectorNode, oa:y, literal(type(_,Y))),
	    rdf_has(SelectorNode, oa:w, literal(type(_,W))),
	    rdf_has(SelectorNode, oa:h, literal(type(_,H)))
	->  true
	;   atomic_list_concat([_,V], ':', Value),
	    atomic_list_concat([X,Y,W,H], ',', V)
	),
	SelectorDict = selector{value:Value,x:X,y:Y,w:W,h:H},
	TargetDict = target{hasSource:Source,
			    hasSelector:SelectorDict,
			    '@id':TargetNode
			   },
	!.

normalize_object(TargetNode, hasTarget, TargetDict) :-
	TargetDict = target{'@id':TargetNode},
	!.


normalize_object(Object, _NormalizedProperty, NormalizedObject) :-
	literal_text(Object, NormalizedObject),
	!.

%%	rdf_add_annotation(+Options:list, -Annotation:url) is det.
%
%	Creates an object of type oa:'Annotation' with uri Annotation
%	from options passed in Options. The required options are:
%       * target(Target)
%         uri of the target
%       * body(Body)
%         literal(tag) or uri of the body
%
%       Optional are:
%	* user(User)
%         defaults to user:anonymous
%	* label(Label)
%         defaults to the body label
%	* field(Field)
%	  defaults to dc:subject
%	* type(Type)
%	  defaults to oa:Tag
%	* typingTime
%         default to 0 (zero)
%	* timestamp(T)
%         defaults to the current time in xsd:dateTime notation
%
%
%	The uri of Annotation is generated by first creating the
%	sha1 hash of the sorted list of predicate/object pairs making
%	up the annotation, and then passing this hash to gv_hash_uri/2
%	to create the final uri.
%
%	Note that if no timestamp is given, each call to this predicate
%	with the same parameters will intentionally yield a new
%	annotation with a new uri (because the changing current time
%	will be part of the hash that is used to create the uri of
%	Annotation).

rdf_add_annotation(Options, Annotation) :-
	option(user(User),      Options, user:anonymous),
	option(field(Field),    Options, dcterms:subject),
	option(typing_time(TT),	Options, 0),
	option(graph(Graph),    Options, 'annotations'),
	option(label(Label),    Options, 'undefined label'),
	option(motivatedBy(Mot), Options, oa:tagging),
	option(body(BodyDict),	 Options),
	option(target(TargetDictList),  Options),

	(   ( option(type(Type), Options), ground(Type))
	->  (  uri_is_global(Type)
	    ->	QType = Type
	    ;	QType = ann_ui:Type
	    )
	;   QType = oa:'Annotation'
	),

	get_time(Time),
	format_time(atom(DefaultTimeStamp), '%FT%T%:z', Time), % xsd:dateTime
	option(timestamp(TimeStamp), Options, DefaultTimeStamp),
	make_target_pairs(TargetDictList, TargetPairs, Graph),

	(   BodyDict.get('@id') = UriString
	->  atom_string(Body, UriString)
	;   atom_string(Literal, BodyDict.get('@value')),
	    Body=literal(Literal) % FIXME make OA compliant
	),

	KeyValue0 = [
	    po(rdf:type, oa:'Annotation'),
	    po(rdf:type, QType),
	    po(oa:annotatedAt, literal(type(xsd:dateTime, TimeStamp))),
	    po(oa:annotatedBy, User),
	    po(oa:motivatedBy, Mot),
	    po(oa:hasBody, Body),
	    po(dcterms:title, literal(Label)),
	    po(ann_ui:annotationField, Field),
	    po(ann_ui:typingTime, literal(type(xsd:integer, TT)))
	    |
	    TargetPairs
	],
	sort(KeyValue0, KeyValue),
	rdf_global_term(KeyValue, Pairs),
	variant_sha1(Pairs, Hash),
	gv_hash_uri(Hash, Annotation),
	maplist(po2rdf(Annotation),Pairs,Triples),
	rdf_transaction(
	     (	 forall(member(rdf(S,P,O), Triples),
			rdf_assert(S,P,O, Graph)))).

po2rdf(S,po(P,O),rdf(S,P,O)).

make_target_pairs([], [], _) :- !.
make_target_pairs([Dict|Tail], [po(oa:hasTarget, TargetNode)|PairTail], Graph) :-
	(   _S = Dict.get(hasSelector)
	->  make_specific_target(Dict, Graph, TargetNode)
	;   atom_string(TargetNode,Dict.get('@id'))
	),
	make_target_pairs(Tail, PairTail, Graph).


make_specific_target(TargetDict, Graph, TargetNode) :-
	SelectorDict = TargetDict.get(hasSelector),
	Shape = SelectorDict.value,
	format(atom(Fragment), '#xywh=percent:~0f,~0f,~0f,~0f',
	       [100*Shape.x,     100*Shape.y,
		100*Shape.width, 100*Shape.height]),
	atom_string(TargetUri, TargetDict.hasSource),
	variant_sha1((TargetUri, Fragment), TargetHash), % FIXME
	debug(target, '~p, ~w, ~w: ~w',
	      [TargetUri, Shape.x, Shape.y, TargetHash]),
	rdf_global_id(oa_target:TargetHash, TargetNode),
	(   rdf_subject(TargetNode)
	->  true % TargetNode already exists
	;   rdf_global_id(oa_selector:TargetHash, SelectorNode),
	    make_selector_node(Fragment, Shape, Graph, SelectorNode),
	    rdf_assert(TargetNode, rdf:type,oa:'SpecificResource', Graph),
	    rdf_assert(TargetNode, oa:hasSource, TargetUri, Graph),
	    rdf_assert(TargetNode, oa:hasSelector, SelectorNode, Graph)
	).

make_selector_node(Fragment, Shape, Graph, Node) :-
	rdf_assert(Node, rdf:type, oa:'FragmentSelector', Graph),
	rdf_assert(Node, rdf:value, literal(Fragment), Graph),
	rdf_assert(Node, dcterms:conformsTo, 'http://www.w3.org/TR/media-frags/', Graph),
	rdf_assert(Node, oa:x, literal(type(xsd:float, Shape.x)), Graph),
	rdf_assert(Node, oa:y, literal(type(xsd:float, Shape.y)), Graph),
	rdf_assert(Node, oa:w, literal(type(xsd:float, Shape.width)), Graph),
	rdf_assert(Node, oa:h, literal(type(xsd:float, Shape.height)), Graph).

%%	rdf_get_annotation(+Annotation:url, -Props:list) is det.
%
%	Unifies the predicate/object pairs of Annotation with
%	Props (using option list notation).

rdf_get_annotation(Annotation, Props) :-
	get_annotation_properties(Annotation, _Graph, Props).

%%	rdf_get_annotation_target(+Annotation, ?TargetUri) is det.
%
%	Get Target uri, abstracting away OA selector stuff
rdf_get_annotation_target(Annotation, TargetUri) :-
	rdf_has(Annotation, oa:hasTarget, TargetNode),
	(   rdfs_individual_of(TargetNode, oa:'SpecificResource')
	->  rdf_has(TargetNode, oa:hasSource, TargetUri)
	;   TargetNode = TargetUri
	).

rdf_get_annotation_by_tfa(Target, Field, Annotator, Graph, [annotation(Annotation)|Props]) :-
	rdf_has_graph(Annotation, oa:hasTarget, Target, Graph),
	rdf_has_graph(Annotation, ann_ui:annotationField, Field, Graph),
	rdf_has_graph(Annotation, oa:annotatedBy, Annotator, Graph),
	get_annotation_properties(Annotation, Graph, Props).

rdf_get_annotation_by_tfa(Target, Field, Annotator, Graph, [annotation(Annotation)|Props]) :-
	rdf_has_graph(TargetNode, oa:hasSource, Target, Graph),
	rdf_has_graph(Annotation, oa:hasTarget, TargetNode, Graph),
	rdf_has_graph(Annotation, ann_ui:annotationField, Field, Graph),
	rdf_has_graph(Annotation, oa:annotatedBy, Annotator, Graph),
	get_annotation_properties(Annotation, Graph, Props).

%%	rdf_get_annotation_properties(+An:uri,+Grph:uri,-Props:list) is nondet.
%
%	Props is an option list with the properties of Annotation
%	in Graph.
%
%	Duplicate keys as in [ key1(a), key1(b) key2(c) ] are grouped
%	into single keys with a value list: [ key1([a,b], key2(c) ].

get_annotation_properties(Annotation, Graph, Props) :-
	findall(P,
		(   rdf(Annotation, Property, Object, Graph),
		    normalize_property(Property, PName),
		    normalize_object(Object, PName, NormalizedObject),
		    P =.. [PName,NormalizedObject]
		),
		Props0),
	sort(Props0, PropsSorted),
	group_duplicate_keys(PropsSorted, Props).

group_duplicate_keys([], []) :-!.
group_duplicate_keys([Option], [Option]) :- !.
group_duplicate_keys([O1, O2 | TailIn], [G|TailOut]) :-
	O1 =.. [Key, Value1],
	O2 =.. [Key, Value2],
	!,
	G  =.. [Key, [Value1, Value2]],
	group_duplicate_keys(TailIn, TailOut).
group_duplicate_keys([O | TailIn], [O|TailOut]) :-
	group_duplicate_keys(TailIn, TailOut),!.



%%	rdf_remove_annotation(+Annotation:url, ?Target:url) is det.
%
%	Removes Annotation on Target. Also succeeds if Annotation
%	does not exists.

rdf_remove_annotation(Annotation, Target) :-
	(   (rdf(Annotation, oa:hasTarget, Target, Target)
	    ;
	    (	rdf(Annotation, oa:hasTarget, TargetNode, Target),
		rdf(TargetNode, oa:hasSource, Target, Target)
	    )
	    )
	->  rdf_remove_annotation_deps(Annotation, Target),
	    rdf_retractall(Annotation, _, _, Target)
	;   true
	).

rdf_remove_target_nodes([],_).
rdf_remove_target_nodes([H|T], Graph) :-
	rdf(H, oa:hasSelector, SelectorNode, Graph),
	rdf_retractall(SelectorNode, _, _, Graph),
	rdf_retractall(H,_,_Graph),
	rdf_remove_target_nodes(T, Graph).


rdf_remove_annotation_deps(Annotation, Graph) :-
	findall(TargetNode, loose_targets(Annotation, Graph, TargetNode), Targets),
	rdf_remove_target_nodes(Targets, Graph).

loose_targets(Annotation, Graph, TargetNode) :-
	rdf(Annotation, oa:hasTarget, TargetNode,  Graph),
	rdf(TargetNode, rdf:type, oa:'SpecificResource', Graph),
	\+ ( rdf(OtherAnnotation, oa:hasTarget, TargetNode, Graph),
	     OtherAnnotation \= Annotation
	   ).




%%	rdf_has_graph(Subject, SuperProperty, Object, Graph) is nondet.
%
%	True if rdf(Subject, Property, Object, Graph) with
%       Property being an rdfs:subPropertyOf SuperProperty.

rdf_has_graph(S,P,O,G) :-
	rdf_graph(G),
	rdf_has(S,P,O,RP),
	rdf(S,RP,O,G).
