"""LLM transports.

Deliberately empty: nothing is re-exported here, so the import graph stays flat
and one-directional (app.services.classifier → app.llm.registry → the concrete
providers → app.llm.base). Import the module you need.
"""
