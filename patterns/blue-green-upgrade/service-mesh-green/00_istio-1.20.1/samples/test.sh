#!/bin/bash
for i in $(seq 1 200); do curl -s -o /dev/null "http://istio.eks-offer.store/productpage"; done