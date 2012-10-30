:- module(oa_annotation, [
			  rdf_has_graph/4,
			  rdf_add_annotation/2,
			  rdf_get_annotation/2,
			  rdf_get_annotation_by_target/3,
			  rdf_remove_annotation/2
			 ]).

:- use_module(library(semweb/rdf_db)).
:- use_module(library(semweb/rdf_label)).
:- use_module(library(oa_schema)).
:- use_module(library(graph_version)).

:- rdf_meta
	rdf_has_graph(r,r,r,r).

rdf_has_graph(S,P,O,G) :-
	rdf_graph(G),
	rdf_has(S,P,O,RP),
	rdf(S,RP,O,G).

rdf_add_annotation(Options, Annotation) :-
	option(type(Type),     Options),
	option(user(User),     Options),
	option(label(Label),   Options),
	option(field(Field),   Options),
	option(target(Target), Options),
	option(body(Body),     Options),
	option(typing_time(TT),	Options, 0),
	option(graph(Graph),   Options, 'annotations'),
	get_time(T),
	format_time(atom(TimeStamp), '%FT%T%:z', T), % xsd:dateTime
	KeyValue0 = [
		     po(rdf:type, oa:'Annotation'),
		     po(rdf:type, an:Type),
		     po(oa:annotated, literal(type(xsd:dateTime, TimeStamp))),
		     po(oa:annotator, User),
		     po(oa:hasTarget, Target),
		     po(oa:hasBody, Body),
		     po(dcterms:title, literal(Label)),
		     po(an:annotationField, Field),
		     po(an:typingTime, literal(type(xsd:integer, TT)))
		    ],
	sort(KeyValue0, KeyValue),
	rdf_global_term(KeyValue, Pairs),
	variant_sha1(Pairs, Hash),
	gv_hash_uri(Hash, Annotation),
	maplist(po2rdf(Annotation),Pairs,Triples),
	gv_graph_triples(Graph, Triples).

po2rdf(S,po(P,O),rdf(S,P,O)).

rdf_get_annotation(Annotation, Props) :-
	get_annotation_properties(Annotation, _Graph, Props).

%%	rdf_get_annotation_by_target(+Target, +Graph, -Props) is nondet.
%
%	Props is an option list with the properties of Annotation
%	in Graph.
%
%	Hack:- You can filter on annotationField(F), user(U) by putting
%	these in the Props as the first two properties...

rdf_get_annotation_by_target(Target, Graph, Props) :-
	rdf(Annotation, oa:hasTarget, Target, Graph),
	get_annotation_properties(Annotation, Graph, Props).

get_annotation_properties(Annotation, Graph, Props) :-
	rdf(Annotation, oa:hasTarget, Target, Graph),
	rdf(Annotation, an:annotationField, Field, Graph),
	rdf_has_graph(Annotation, oa:annotator, User, Graph),
	rdf_has_graph(Annotation, oa:hasBody, Body, Graph),
	rdf_has_graph(Annotation, dcterms:title, Lit, Graph),
	literal_text(Lit, Label),
	rdf(Annotation, rdf:type, Type, Graph),
	rdf_global_id(an:LocalType, Type),
	Props = [
		 % these two first, sorry!
		 annotationField(Field),
		 user(User),

		 % then the rest...
		 target(Target),
		 annotation(Annotation),
		 label(Label),
		 body(Body),
		 type(LocalType)
	].

%%	rdf_remove_annotation(+Annotation, ?Target) is det.
%
%	Removes Annotation on Target. Also succeeds if Annotation
%	does not exists.

rdf_remove_annotation(Annotation, Target) :-
	(   rdf(Annotation, oa:hasTarget, Target, Target)
	->  rdf_retractall(Annotation, _, _, Target)
	;   true
	).
