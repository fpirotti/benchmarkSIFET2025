# Benchmark SIFET 2025

**“Classificazione di nuvole di punti da drone”**

Francesco Pirotti, Enrico Magazzino

*CIRGEO Centro Interdipartimentale di Ricerca di Geomatica / TESAF Dipartimento Territorio e Sistemi Agroforestali, Università di Padova*

## Obiettivi

Suddividere i punti rilevati con sensore laser scanner L2 in parti omogenee (segmenti o oggetti), in base a criteri estratti dalle variabili dispoinibili.

## Materiale

Il benchmark mette a disposizione diversi prodotti da rilievo con drone con camere RGB, multispettrali e LiDAR su una zona agricola

## Metodi

come colore, texture, forma o contesto spaziale.

Descrittori geometrici da intorno di 50 cm e 1 m estratti con 32 threads -

![](images/clipboard-2581011368.png){width="373"}

I descrittori sono stati scalati e trasformati rispetto alla loro mediana ed alla loro deviazione standard in quanto spesso non seguono una distribuzione nornale .
The standard mathematical **symbol for the median** is:
 

$$
z = \frac{x - \tilde{x}}{\text{MAD}(x)}

\quad \text{where} \quad \tilde{x} = \text{median}(x)
$$

 

## Risultati

I dati sono visibili nel visualizzatore online basato su Potree [QUI](https://www.cirgeo.unipd.it/pointclouds/sifetBenchmark2025/).

La nuvola dopo segmentazione è disponibile QUI
