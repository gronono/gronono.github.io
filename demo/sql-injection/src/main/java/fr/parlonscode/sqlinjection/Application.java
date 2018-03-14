package fr.parlonscode.sqlinjection;

import java.util.Arrays;

import org.springframework.boot.CommandLineRunner;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.context.annotation.Bean;

@SpringBootApplication
public class Application {

	public static void main(String[] args) {
		SpringApplication.run(Application.class, args);
	}
	
	@Bean
	public CommandLineRunner insertData(PersonRepository repo) {
		return (args) -> {
			Arrays.asList("phillwebb", "wilkinsona", "dsyer", "snicoll").stream()
				.map(name -> new Person(name))
				.forEach(person -> repo.save(person));
		};
	}
}
