import logging
"""
Example secure plugin for QLC.
This module enriches a dataset with mock metadata or performs a secure transformation.
"""

def enrich_dataset(dataset):
    logging.info("[SECURE PLUGIN] Enriching dataset with mock metadata...")
    dataset.attrs["secure_enrichment"] = "applied"
    return dataset
