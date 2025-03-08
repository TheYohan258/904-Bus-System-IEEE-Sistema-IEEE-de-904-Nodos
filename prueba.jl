using LinearAlgebra
using DataFrames
using CSV
using PrettyTables
using Plots
using Clustering
using Dates
using MultivariateStats
using Interpolations

##___________________________________________________________________________
function carga_datos() # Función para cargar los datos
    lin = DataFrame(CSV.File("liness.csv")) # Datos de las líneas
    nod = DataFrame(CSV.File("nodess.csv")) # Datos de los nodos
    dem = DataFrame(CSV.File("Demandas.csv")) # Datos de las demandas
    dat_solar = DataFrame(CSV.File("SolarData.csv")) # Datos de la generación solar
    num_nod = nrow(nod) # Número de nodos
    num_lin = nrow(lin) # Número de líneas
    return lin, nod, num_lin, num_nod, dem, dat_solar # Se retornan los DataFrames y el número de nodos y líneas
end
##___________________________________________________________________________
function crear_diccionario(filepath::String) # Función para crear un diccionario
    lines_df = DataFrame(CSV.File(filepath)) # Leer el archivo CSV
    # Crear un diccionario para almacenar los valores
    diccionario = Dict{Int, Int}() # Diccionario vacío
    # Recorrer cada fila del DataFrame
    for row in eachrow(lines_df) # Se recorre cada fila
        # Obtener los valores de las columnas FROM y TO sin la letra "N"
        from_value = parse(Int, replace(row.FROM, "N" => "")) # Se obtiene el valor de FROM
        to_value = parse(Int, replace(row.TO, "N" => "")) # Se obtiene el valor de TO
        # Almacenar los valores en el diccionario
        diccionario[from_value] = to_value # Se almacena en el diccionario
    end 
    return diccionario
end
##___________________________________________________________________________
function crear_diccionario_nodes(filepath::String) # Función para crear un diccionario
    nodes_df = DataFrame(CSV.File(filepath)) # Leer el archivo CSV
    # Crear un diccionario para almacenar los valores
    diccionario1 = Dict{Int, Int}() # Diccionario vacío
    # Recorrer cada fila del DataFrame
    for row in eachrow(nodes_df) # Se recorre cada fila
        # Obtener los valores de las columnas NUMBER y NAME sin la letra "N"
        number_value = parse(Int, replace(row.NAME, "N" => "")) # Se obtiene el valor de NUMBER
        name_value = parse(Int, replace(row.NUMBER, "N" => "")) # Se obtiene el valor de NAME
        # Almacenar los valores en el diccionario
        diccionario1[number_value] = name_value # Se almacena en el diccionario
    end
    
    return diccionario1
end
##___________________________________________________________________________
function crear_Ykmimg(lin, num_nod) # Función para crear la matriz de admitancias
    num_lin = nrow(lin) # Número de líneas
    Ykm = zeros(Complex{Float64}, num_nod, num_nod) # Matriz de admitancias (compleja)
    for i in 1:num_lin # Se recorre cada línea
        k = lin.FROM[i] # Nodo de inicio
        m = lin.TO[i] # Nodo final
        Z_km = lin.R[i] + lin.X[i]*1im # Impedancia de la línea (compleja)
        Y_km = 1 / Z_km # Admitancia de la línea (inversa de la impedancia)
        Bs = lin.B[i]*1im/2 # Susceptancia de la línea
        Ykm[k, m] -= Y_km # Fuera
        Ykm[m, k] -= Y_km # Fuera
        Ykm[k, k] += Y_km + Bs # Diagonal
        Ykm[m, m] += Y_km + Bs # Diagonal
    end
    return Ykm 
end
##___________________________________________________________________________
function y_bus_inv(lin, num_nod) # Función para invertir la matriz de admitancias
    Ykm = crear_Ykmimg(lin, num_nod) # Se crea la matriz de admitancias
    Ykm_inv = pinv(Ykm) # Se invierte la matriz de admitancias
    return Ykm_inv
end
##___________________________________________________________________________
function crear_ynn_yns(Ykm, lin, nod) # Función para crear las matrices Ynn y Yns
    s = findfirst(nod.TYPE .== 3) # Nodo slack
    Yn = Ykm[setdiff(1:end, s), setdiff(1:end, s)] # Matriz de admitancias de los nodos sin slack
    Yns = Ykm[setdiff(1:end, s), s] # vector de admitancias de los nodos quitando el slack 
    return Yn, Yns
end
##___________________________________________________________________________
function calcular_vn_vs(nod) # Función para calcular los voltajes
    num_nod = nrow(nod) # Número total de nodos
    s = findfirst(nod.TYPE .== 3) # Identificar el nodo slack
    num_pq = num_nod - 1 # Número de nodos sin slack
    Vn = ones(Complex{Float64}, num_pq) # Inicializar con valores complejos
    Vs = 1.0 + 0.0im # Voltaje del slack
    return Vn, Vs
end
##___________________________________________________________________________
function calcular_potencia_neta(nodes) # Función para calcular la potencia Sn
    Sn = ComplexF64[]  # Vector de potencias complejas
    for i in 2:size(nodes, 1)  # Omitimos el nodo slack
        push!(Sn, (nodes[i, :PLOAD] - nodes[i, :PGEN]) + im * (nodes[i, :QLOAD] - nodes[i, :QGEN])) # Se calcula la potencia neta
    end
    return Sn
end
##___________________________________________________________________________
function flujo_punto_fijo(ynn, yns, sn, vn, vs) # Función para el flujo de potencia
    max_iter = 3 # Número máximo de iteraciones
    tol = 1 # Tolerancia ajustada (ajustar para segun la precision deseada)
    num_nodos = length(sn) # Número de nodos
    errores = zeros(max_iter) # Vector de errores
    ite = zeros(max_iter) # Vector de iteraciones
    for i in 1:max_iter # Se recorre el número de iteraciones
        Vn_ant = copy(vn) # Voltaje anterior
        vn = ynn \ (conj.(sn ./ vn) .- yns * vs) # Cálculo de los voltajes
        #vs = 1.0 + 0.0im # Voltaje del slack
        errores[i] = norm(vn - Vn_ant) # Cálculo del error
        ite[i] = i # Número de iteración
        println("Iteración $i, Error: $(errores[i])") # Mensaje de depuración
        if errores[i] < tol # Condición de convergencia
            println("Convergencia alcanzada en iteración $i con error $(errores[i])") # Mensaje de depuración
            errores = errores[1:i] # Se actualiza el vector de errores
            ite = ite[1:i] # Se actualiza el vector de iteraciones
            break
        end
    end
    return vn, vs, errores, ite # Se retornan los voltajes, errores e iteraciones
end
##___________________________________________________________________________
function leer_demandas(filepath::String) # Función para leer las demandas
    # Cargar datos del archivo CSV
    dem = DataFrame(CSV.File(filepath)) # Se carga el archivo CSV
    
    # Lista para almacenar los vectores de demanda
    demandas = Vector{Vector{Float64}}(undef, nrow(dem)) # Vector vacío
    
    # Recorrer cada fila del DataFrame
    for i in 1:nrow(dem) # Se recorre cada fila
        # Convertir la fila en un vector columna
        vector_columna = Vector{Float64}(dem[i, :]) # Se convierte en un vector columna
        # Almacenar el vector columna en la lista
        demandas[i] = vector_columna # Se almacena en la lista
    end
    return demandas
end
##___________________________________________________________________________
function agrupar_por_dias(file_path::String) # Función para agrupar los datos por día
    data = CSV.read(file_path, DataFrame) # Se lee el archivo CSV
    data.Fecha = Date.(data.Fecha, "m/d/yyyy") # Se convierte la columna Fecha a tipo Date
    datos_agrupados = Dict{Int, DataFrame}() # Diccionario vacío
    for row in eachrow(data) # Se recorre cada fila
        dia = dayofyear(row.Fecha) # Se obtiene el día del año
        if !haskey(datos_agrupados, dia) # Si no existe la clave en el diccionario
            datos_agrupados[dia] = DataFrame(Fecha=Date[], Hora=Time[], Potencia=Float64[]) # Se crea un DataFrame vacío
        end
        push!(datos_agrupados[dia], row) # Se agrega la fila al DataFrame correspondiente
    end
    return datos_agrupados
end
##___________________________________________________________________________
function graficar_generacion_por_dia(datos_agrupados::Dict{Int, DataFrame}) # Función para graficar la generación solar por día
    # Se Crea una figura para las gráficas
    p = plot(title="Generación Solar Diaria", xlabel="Tiempo en muestras", ylabel="Potencia (W)", legend=false) # Se crea la figura
    
    # Recorrer cada día y agregar una gráfica a la figura
    for (dia, datos) in datos_agrupados # Se recorre cada día
        tiempo = 1:nrow(datos) # Se toma el tiempo
        plot!(p, tiempo, datos.Potencia, label="Día $dia") # Se grafica la potencia
    end
    
    # Mostrar la figura
    display(p)
    savefig("generacion_solar.png") # Guardar la figura como archivo PNG
end
##___________________________________________________________________________
function guardar_bloques_en_vectores(datos_agrupados::Dict{Int, DataFrame}) # Función para guardar los bloques en vectores
    # Se crea un vector de DataFrames con el tamaño de los datos agrupados (1 dia)
    vectores_dias = Vector{DataFrame}(undef, length(datos_agrupados)) # Vector de DataFrames
    
    # Inicializar los DataFrames en el vector
    for i in 1:length(datos_agrupados) # Se recorre la longitud de los datos agrupados
        vectores_dias[i] = DataFrame() # Se crea un DataFrame vacío
    end

    # Recorrer el diccionario y almacenar cada bloque en el DataFrame correspondiente
    for (dia, datos) in datos_agrupados # Se recorre cada día
        vectores_dias[dia] = datos # Se almacena el bloque en el DataFrame correspondiente
    end
    
    return vectores_dias 
end
##___________________________________________________________________________
function clusterizar_generacion_solar(datos_agrupados::Dict{Int, DataFrame}, k::Int) # Función para clusterizar la generación solar
    # Crear una matriz de 365 filas y 288 columnas
    matriz = zeros(Float64, 365, 288) # Matriz de ceros

    # Llenar la matriz con los valores de potencia
    for (dia, datos) in datos_agrupados # Se recorre cada día
        for (i, row) in enumerate(eachrow(datos)) # Se recorre cada fila
            muestra = Int((row.Hora - Time(0, 0)) / Minute(5)) + 1 # Se obtiene la muestra
            if dia <= 365 && muestra <= 288 # Si el día y la muestra están dentro de los límites
                matriz[dia, muestra] = row.Potencia # Se almacena la potencia en la matriz
            end
        end
    end

    # Aplicar K-means
    resultado = kmeans(transpose(matriz), k) # Se aplica el algoritmo K-means

    # Crear una figura para las gráficas de clusterización
    colores = [:black, :red, :blue, :purple, :orange, :cyan] # Colores para los clusters

    # Graficar los días coloreados por cluster
    o = plot(title="Clusterización de Generación Solar Diaria", xlabel="Tiempo en muestras", ylabel="Potencia (W)") # Se crea la figura
    for i in 1:365 # Se recorre cada día
        cluster_id = resultado.assignments[i] # Se obtiene el ID del cluster
        plot!(o, 1:288, matriz[i, :], color=colores[cluster_id], alpha=0.3, label="") # Se grafica la potencia
    end

    # Mostrar la figura
    display(o)
    savefig("Clusterizacion_solar.png") # Guardar la figura como archivo PNG (comentar si no se desea guardar)

    # Mostrar los centroides
    grafica_centroides = plot(title="Centroides de los Clusters", xlabel="Tiempo en muestras", ylabel="Potencia") # Se crea la figura

    for i in 1:k # Se recorre cada cluster
        plot!(grafica_centroides, 1:288, resultado.centers[:, i], color=colores[i], linewidth=3, label="Cluster $i") # Se grafica el centroide
    end

    # Mostrar la gráfica de los centroides
    display(grafica_centroides) 
    savefig("Grafica_centroides") # Guardar la figura como archivo PNG (comentar si no se desea guardar)

    # Seleccionar el cluster con el valor más alto de los centroides
    max_cluster_index = argmax([maximum(resultado.centers[:, i]) for i in 1:k]) # Se selecciona el cluster con el valor más alto
    max_cluster_data = resultado.centers[:, max_cluster_index] # Se obtienen los datos del cluster seleccionado

    # Interpolar los datos del cluster seleccionado a muestras de 1 minuto
    tiempo_original = collect(0:5:1435)  # Tiempos originales en minutos (cada 5 minutos)
    tiempo_interpolado = collect(0:1439)  # Tiempos deseados en minutos (cada 1 minuto)
    interpolacion = LinearInterpolation(tiempo_original, max_cluster_data, extrapolation_bc=Line()) # Interpolación lineal
    datos_interpolados = [interpolacion(t) for t in tiempo_interpolado] # Datos interpolados

    # Normalizar los datos interpolados a p.u. con una base de 400
    sbase = 400.0 # Base de potencia
    datos_interpolados_pu = datos_interpolados ./ sbase # Datos normalizados a p.u.

    # Convertir los datos interpolados a un vector
    datos_interpolados_pu_vector = collect(datos_interpolados_pu) # Convertir a un vector

    # Graficar los datos interpolados
    grafica_interpolada = plot(title="Datos Interpolados del Cluster Seleccionado", xlabel="Tiempo en minutos", ylabel="Potencia (p.u.)") # Se crea la figura
    plot!(grafica_interpolada, tiempo_interpolado, datos_interpolados_pu, color=:red, linewidth=2, label="Cluster $max_cluster_index Interpolado") # Se grafican los datos

    # Mostrar la gráfica de los datos interpolados
    display(grafica_interpolada) 
    savefig("interpolacion_solar.png") # Guardar la figura como archivo PNG (comentar si no se desea guardar)

    # Guardar los datos interpolados en un archivo CSV
    CSV.write("datos_interpolados.csv", DataFrame(Tiempo=tiempo_interpolado, Potencia=datos_interpolados_pu_vector)) # Se guardan los datos interpolados en un archivo CSV

    return datos_interpolados_pu_vector
end
##___________________________________________________________________________
function calcular_potencia_neta2(nodes, demandas, generacion) # Función para calcular la potencia Sn
    Sn1 = ComplexF64[]  # Vector de potencias complejas
    for i in 2:size(nodes, 1)  # Omitimos el nodo slack
        if i <= 55 # Se ajusta la demanda en el nodo 55 (demanda que cambia cada minuto desde el nodo 1 hasta el 55)
            PLOAD = nodes[i, :PLOAD] + demandas[i] # Se ajusta la demanda
        else
            PLOAD = nodes[i, :PLOAD] # Se mantiene la demanda tal como se encuentra
        end
        PGEN = i == 8 ? generacion : 0.0  # Ajustar la generación en el nodo 8 (cambiar si lo desea)
        QLOAD = nodes[i, :QLOAD] # Se mantiene la demanda reactiva
        QGEN = nodes[i, :QGEN] # Se mantiene la generación reactiva
        push!(Sn1, (PLOAD - PGEN) + im * (QLOAD - QGEN)) # Se calcula la potencia neta
    end
    return Sn1
end
##___________________________________________________________________________
function graficar_voltajes_por_minuto(voltajes_por_minuto) # Función para graficar los voltajes por minuto
    p = plot(title="Voltajes en p.u. por minuto", xlabel="Minuto", ylabel="Voltaje (p.u.)") # Se crea la figura
    for i in 1:length(voltajes_por_minuto[1]) # Se recorre cada nodo
        voltajes_nodo = [voltajes[minuto][i] for minuto in 1:length(voltajes_por_minuto)] # Se obtienen los voltajes del nodo
        plot!(p, 1:length(voltajes_por_minuto), voltajes_nodo, label="Nodo $i") # Se grafican los voltajes del nodo
    end
    display(p)
    savefig("voltajes_por_minuto.png") # Guardar la figura como archivo PNG (comentar si no se desea guardar)
end
##___________________________________________________________________________
function main() # Función principal
    #filepath = "c:/Users/Acer/OneDrive/Escritorio/computacionales/Clase 4/nodes.csv" # modificar la direccion del archivo nodes.csv
    #filepath = "c:/Users/Acer/OneDrive/Escritorio/computacionales/Clase 4/lines.csv" # modificar la direccion del archivo lines.csv
    archivo = "c:/Users/Acer/OneDrive/Escritorio/computacionales/Clase 4/SolarData.csv" # modificar la direccion del archivo Solar.Data
    filepath = "c:/Users/Acer/OneDrive/Escritorio/computacionales/Clase 4/Demandas.csv" # # modificar la direccion del archivo Demandas.csv
    demandas = leer_demandas(filepath)
    #diccionario_nodes = crear_diccionario_nodes(filepath) (no se activan si se usa el archivo nodess.csv y liness.csv)
    #diccionario = crear_diccionario(filepath) (no se activan si se usa el archivo liness.csv)
    lin, nod, num_lin, num_nod, dem, dat_solar = carga_datos() # Se cargan los datos
    datos_agrupados = agrupar_por_dias(archivo) # Se llaman los datos agrupados
    Ykm1 = crear_Ykmimg(lin, num_nod) # se llama la ybus
    ykm1inv = y_bus_inv(lin, num_nod)  # se llama la ybus^-1
    ynn, yns = crear_ynn_yns(Ykm1, lin, nod) # se llama ynn(sin slack), yns(vector fila sin slack)
    sn = calcular_potencia_neta(nod) # se llama el vector de potencia aparente
    vn, vs = calcular_vn_vs(nod) # se llama el vector vn y vs
    vn_final, vs_final, errores, ite = flujo_punto_fijo(ynn, yns, sn, vn, vs) # se llama a la funcion que corre el punto fijo
    datos_agrupados = agrupar_por_dias(archivo) # Se agrupan los datos por día
    vectores_dias = guardar_bloques_en_vectores(datos_agrupados) # Se guardan los bloques en vectores

    println("Matriz de Ybus")
    pretty_table(Ykm1)
    
    println("Matriz de Ybus inversa")
    pretty_table(ykm1inv)

    println("Matriz de Ynn")
    pretty_table(ynn)

    println("Matriz de Yns")
    pretty_table(yns)

    println("Vector de potencias")
    pretty_table(DataFrame(Potencia=sn))

    println("Vector de voltajes finales")
    pretty_table(DataFrame(Voltaje=vn_final))

    println("Errores por iteración")
    pretty_table(DataFrame(Iteracion=ite, Error=errores))
    ##___________________________________________________________________________
    # Graficar el gráfico de convergencia
    plot(ite, log10.(errores), xlabel="Iteraciones", ylabel="Log10(Error)", title="Convergencia del Método de Punto Fijo", legend=false)
    savefig("convergencia.png") # Guardar el gráfico como archivo PNG (comentar si no se desea guardar)
    ##___________________________________________________________________________  
    graficar_generacion_por_dia(datos_agrupados) # Se grafica la generación solar por día 
    ##___________________________________________________________________________
    # Aplicar k-means y graficar la clusterización de la generación solar por día
    k = 3 # Número de clusters deseado
    datos_interpolados = clusterizar_generacion_solar(datos_agrupados, k) # Se clusteriza la generación solar
    ##___________________________________________________________________________
    # Calcular la potencia neta para cada minuto y ejecutar el flujo de potencia
    voltajes_por_minuto = [] # Vector vacío
    #for minuto in 1:1440 # Se recorre cada minuto
    #    if minuto <= length(demandas) && minuto <= length(datos_interpolados) # Si el minuto está dentro de los límites
    #        sn_nuevo = calcular_potencia_neta2(nod, demandas[minuto], datos_interpolados[minuto]) # Se calcula la potencia neta
    #        vn, vs, errores, ite = flujo_punto_fijo(ynn, yns, sn_nuevo, vn, vs) # Se ejecuta el flujo de potencia
    #        push!(voltajes_por_minuto, vn) # Se almacena el vector de voltajes
    #        println("Voltajes en minuto $minuto: $vn") # Se imprime el vector de voltajes
    #    else
    #        println("Índice fuera de los límites: $minuto") # Mensaje de depuración
    #    end
    #end
    #return nothing
end
main()