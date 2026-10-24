// Times Go's regexp over the corpus: counts matches per file, median of ROUNDS rounds. Output: engine,workload,median_ms,count
package main

import (
	"bufio"
	"bytes"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"time"
)

func main() {
	workloads, _ := os.Open(os.Args[1])
	var files [][]byte
	filepath.Walk(os.Args[2], func(p string, i os.FileInfo, err error) error {
		if err == nil && !i.IsDir() && strings.HasSuffix(p, ".swift") {
			b, _ := os.ReadFile(p)
			files = append(files, b)
		}
		return nil
	})
	if os.Getenv("CONCAT") != "" { // one buffer: measures scan speed without per-call overhead
		files = [][]byte{bytes.Join(files, nil)}
	}
	sc := bufio.NewScanner(workloads)
	for sc.Scan() {
		parts := strings.SplitN(sc.Text(), "\t", 2)
		re := regexp.MustCompile(parts[1])
		var times []float64
		count := 0
		for r := 0; r < 9; r++ {
			start := time.Now()
			count = 0
			for _, f := range files {
				count += len(re.FindAllIndex(f, -1))
			}
			times = append(times, float64(time.Since(start).Nanoseconds())/1e6)
		}
		sort.Float64s(times)
		fmt.Printf("Go regexp,%s,%.2f,%d\n", parts[0], times[len(times)/2], count)
	}
}
