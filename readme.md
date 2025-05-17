# Benchmark SIFET 2025

**“Classificazione di nuvole di punti da drone”**

Francesco Pirotti, Enrico Magazzino

*CIRGEO Centro Interdipartimentale di Ricerca di Geomatica / TESAF Dipartimento Territorio e Sistemi Agroforestali, Università di Padova*

## Obiettivi

Suddividere i punti rilevati con sensore laser scanner L2 in parti omogenee (segmenti o oggetti), in base a criteri estratti dalle variabili dispoinibili.

## Materiale e Metodi

### Dati utilizzati

Il benchmark mette a disposizione diversi prodotti da rilievo con drone con camere RGB, multispettrali e LiDAR su una zona agricola. La nuvola di punti contiene 1'248'152'076 (1.25 x 10\^9) punti.

La procedura di segmentazione assistita viene implementata usando tre combinazioni:

1.  solo nuvola di punti e solo descrittori geometrici

2.  solo nuvola di punti e descrittori geometici + RGB + intensità

### Software

Per la procedura di segmentazione vengono utilizzati quasi tutti algoritmi e applicativi a codice aperto (open source - OS) di ultima generazione, "chiamati" in una procedura in ambiente R per uniformare il processo. In particolare vengono usati Lastools, lasR, LidR, CloudGeometry e H2O.

Per la procedura di creazione dell'ortoimmagine multispettrale è stato utilizzato Metashape-pro.

### Capacità di calcolo

Per l'elaborazione viene usato un calcolatore assemblato SuperMicro, con le seguenti caratteristiche:

::: list
-   CPU(s): 384

-   Model name: AMD EPYC 9654 96-Core Processor

-   CPU family: 25

-   Model: 17

-   Thread(s) per core: 2

-   Core(s) per socket: 96

-   CPU max MHz: 3707.8120

-   CPU min MHz: 1500.0000

-   BogoMIPS: 4800.10

-   Memory: total: 770 GiB
:::

### Area di studio

<img src="images/Layout 1.jpeg" width="600"/>

## Metodi

L'obiettivo è la segmentazione, realizzata in modalità semi-automatica, mediante la suddivisione dei punti in cluster sulla base delle loro caratteristiche distintive.

L'unità elementare usata per la segmentazione è il singolo punto nella nuvola di punti

Descrittori geometrici da intorno di 50 cm e 0.25 m estratti con 32 CPU. I descrittori geometrici sono noti da letteratura e sono qui estratti con la libreria [R "CloudGeometry"](https://github.com/fpirotti/CloudGeometry) disponibile su Github. Questa libreria sfrutta la capacità di utilizzo del calcolo parallelo multi-CPU dei moderni calcolatori. Questo passaggio è fondamentale dato il numero elevato di punti (\> 1e9 ).

![](images/clipboard-1084557557.png){width="302"}

<img src="images/clipboard-2581011368.png" width="373"/>

I descrittori sono stati scalati e trasformati rispetto alla loro mediana ed alla loro deviazione standard in quanto spesso non seguono una distribuzione nornale . The standard mathematical **symbol for the median** is:

$$
z = \frac{x - \tilde{x}}{\text{MAD}(x)}
$$

$$  
\quad \text{dove} \quad \tilde{x} = \text{mediana}(x)
$$

La segmentazione viene poi eseguita con il metodo K-means su queste variabili e aggiungendo RGB. Vengono imposte 10 diversi cluster.

## Risultati

I dati sono visibili online [QUI](https://www.cirgeo.unipd.it/pointclouds/sifetBenchmark2025/).

La nuvola dopo segmentazione è disponibile per download QUI.

## Discussione

Nel procedimento sono stati notati molti limiti nell'utilizzo di alcuni algoritmi implementati unicamente su R usando lidR e lasR. In primis lidR carica in un data.frame R i dati, ovvero in una struttura non ottimizzata. La libreria lasR invece utilizza quasi esclusivamente l'ambiente di memoria C++ dunque viene gestito meglio. Lastools invece sfrutta al meglio la capacità di calcolo parallelo, senza complicazioni dovute ad alcune strategie di condivisione della memoria utilizzate da R. Lastools viene lo stesso usato tramite R chiamando il programma con il comando system. L'utilizzo di alternative, per rendere il flusso di processo totalmente OS, è sicuramente da verificare, con adeguata attenzione all'implementazione di ogni singolo algoritmo per quanto riguarda l'utilizzo della memoria per ogni processo eseguito in parallelo.
